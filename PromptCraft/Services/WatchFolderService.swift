import Combine
import Foundation
import UserNotifications

final class WatchFolderService: ObservableObject {
    static let shared = WatchFolderService()

    @Published private(set) var isWatching: Bool = false

    private let configService = ConfigurationService.shared
    private let styleService = StyleService.shared
    private let providerManager = LLMProviderManager.shared
    private let promptAssembler = PromptAssembler.shared
    private let historyService = HistoryService.shared
    private let contextEngine = ContextEngineService.shared
    private let notificationService = NotificationService.shared
    private let clipboardService = ClipboardService.shared
    private let postProcessor = PostProcessor.shared

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let monitorQueue = DispatchQueue(label: "com.promptcraft.watchFolder", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?

    /// Maximum file size to process (100 KB).
    private let maxFileSize: UInt64 = 100 * 1024

    /// Debounce interval to batch rapid file system events.
    private let scanDebounceInterval: TimeInterval = 1.0
    private var pendingScanWorkItem: DispatchWorkItem?

    // MARK: - Processed File Tracking

    private var processedFilenames: Set<String> {
        get {
            let key = AppConstants.UserDefaultsKeys.watchFolderProcessedFiles
            let array = UserDefaults.standard.stringArray(forKey: key) ?? []
            return Set(array)
        }
        set {
            let key = AppConstants.UserDefaultsKeys.watchFolderProcessedFiles
            UserDefaults.standard.set(Array(newValue), forKey: key)
        }
    }

    // MARK: - Lifecycle

    private init() {
        observeConfigChanges()
    }

    deinit {
        stopWatching()
    }

    // MARK: - Public API

    func startIfEnabled() {
        let config = configService.configuration
        if config.watchFolderEnabled {
            startWatching()
        }
    }

    // MARK: - Configuration Observation

    private struct WatchFolderKey: Equatable {
        let enabled: Bool
        let path: String
    }

    private func observeConfigChanges() {
        configService.$configuration
            .map { WatchFolderKey(enabled: $0.watchFolderEnabled, path: $0.watchFolderPath) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] key in
                guard let self else { return }
                if key.enabled {
                    self.stopWatching()
                    self.startWatching()
                } else {
                    self.stopWatching()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Start / Stop

    private func startWatching() {
        guard !isWatching else { return }

        let config = configService.configuration
        let expandedPath = (config.watchFolderPath as NSString).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expandedPath, isDirectory: true)

        // Create directory if needed
        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            do {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                Logger.shared.info("WatchFolderService: Created inbox directory at \(expandedPath)")
            } catch {
                Logger.shared.error("WatchFolderService: Failed to create inbox directory", error: error)
                disableGracefully()
                return
            }
        }

        // Verify directory is accessible
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            Logger.shared.warning("WatchFolderService: Path is not a directory: \(expandedPath)")
            disableGracefully()
            return
        }

        fileDescriptor = open(expandedPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            Logger.shared.error("WatchFolderService: Failed to open directory for monitoring: \(expandedPath)")
            disableGracefully()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: monitorQueue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleScan()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        dispatchSource = source
        source.resume()

        DispatchQueue.main.async {
            self.isWatching = true
        }

        Logger.shared.info("WatchFolderService: Started watching \(expandedPath)")

        // Perform an initial scan for any files already present
        scheduleScan()
    }

    private func stopWatching() {
        pendingScanWorkItem?.cancel()
        pendingScanWorkItem = nil
        processingTask?.cancel()
        processingTask = nil

        if let source = dispatchSource {
            source.cancel()
            dispatchSource = nil
        }

        DispatchQueue.main.async {
            self.isWatching = false
        }

        Logger.shared.info("WatchFolderService: Stopped watching")
    }

    private func disableGracefully() {
        Logger.shared.warning("WatchFolderService: Disabling watch folder due to inaccessible path")
        stopWatching()
        DispatchQueue.main.async {
            self.configService.update { $0.watchFolderEnabled = false }
        }
    }

    // MARK: - Scanning

    private func scheduleScan() {
        pendingScanWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanForNewFiles()
        }
        pendingScanWorkItem = work
        monitorQueue.asyncAfter(deadline: .now() + scanDebounceInterval, execute: work)
    }

    private func scanForNewFiles() {
        let config = configService.configuration
        let expandedPath = (config.watchFolderPath as NSString).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expandedPath, isDirectory: true)

        let fm = FileManager.default

        // Check directory still exists
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            DispatchQueue.main.async { [weak self] in
                self?.disableGracefully()
            }
            return
        }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            Logger.shared.error("WatchFolderService: Failed to list directory contents", error: error)
            return
        }

        let processed = processedFilenames

        let txtFiles = contents.filter { url in
            guard url.pathExtension.lowercased() == "txt" else { return false }
            let name = url.lastPathComponent
            // Skip already-processed files and output files
            guard !processed.contains(name) else { return false }
            guard !name.hasSuffix("-optimized.txt") && !name.hasSuffix("-error.txt") else { return false }
            return true
        }

        guard !txtFiles.isEmpty else { return }

        for fileURL in txtFiles {
            processFile(at: fileURL)
        }
    }

    // MARK: - File Processing

    private func processFile(at fileURL: URL) {
        let filename = fileURL.lastPathComponent

        // Check file size
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attrs[.size] as? UInt64 {
                if size == 0 {
                    Logger.shared.info("WatchFolderService: Skipping empty file: \(filename)")
                    markProcessed(filename)
                    return
                }
                if size > maxFileSize {
                    Logger.shared.info("WatchFolderService: Skipping oversized file (\(size) bytes): \(filename)")
                    markProcessed(filename)
                    return
                }
            }
        } catch {
            Logger.shared.warning("WatchFolderService: Could not read file attributes for \(filename)", error: error)
            return
        }

        // Read file contents
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            Logger.shared.error("WatchFolderService: Failed to read file \(filename)", error: error)
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logger.shared.info("WatchFolderService: Skipping file with only whitespace: \(filename)")
            markProcessed(filename)
            return
        }

        // Mark as processed immediately to prevent re-processing during async work
        markProcessed(filename)

        Logger.shared.info("WatchFolderService: Processing file: \(filename)")

        let config = configService.configuration
        let baseName = (filename as NSString).deletingPathExtension
        let folderURL = fileURL.deletingLastPathComponent()

        // Resolve style
        let styleID = config.watchFolderStyleID
            ?? config.enabledStyleIDs.first
            ?? DefaultStyles.defaultStyleID
        guard let style = styleService.getByIdIncludingInternal(styleID) else {
            Logger.shared.error("WatchFolderService: Style not found for ID \(styleID)")
            writeErrorFile(
                folder: folderURL,
                baseName: baseName,
                error: "Style not found. Please configure a valid style in Watch Folder settings."
            )
            return
        }

        // Check API key
        if config.selectedProvider != .ollama && config.selectedProvider != .promptCraftCloud {
            guard KeychainService.shared.hasAPIKey(for: config.selectedProvider) else {
                Logger.shared.error("WatchFolderService: No API key for \(config.selectedProvider.displayName)")
                writeErrorFile(
                    folder: folderURL,
                    baseName: baseName,
                    error: "No API key configured for \(config.selectedProvider.displayName). Please set one in Settings > AI Providers."
                )
                return
            }
        }

        let provider = providerManager.activeProvider
        let startTime = Date()

        processingTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            do {
                let assembled = await self.promptAssembler.assemble(
                    rawInput: trimmed,
                    style: style,
                    providerType: config.selectedProvider,
                    verbosity: config.outputVerbosity
                )

                var messages: [LLMMessage] = [
                    LLMMessage(role: .system, content: assembled.systemMessage)
                ]
                messages.append(contentsOf: assembled.messages)

                let parameters = LLMRequestParameters(
                    model: config.selectedModelName,
                    temperature: config.temperature,
                    maxTokens: config.maxOutputTokens
                )

                var output = ""
                let stream = provider.streamCompletion(messages: messages, parameters: parameters)
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    output += chunk
                }

                // Post-process
                var post = self.postProcessor.process(
                    outputText: output,
                    tier: assembled.complexity.tier,
                    maxOutputWords: assembled.complexity.maxOutputWords
                )

                if post.shouldRetryForMetaLeak {
                    var retryMessages = messages
                    if let first = retryMessages.first, first.role == .system {
                        retryMessages[0] = LLMMessage(
                            role: .system,
                            content: first.content + "\n\nOutput ONLY the prompt. Zero meta-commentary."
                        )
                    }

                    var retriedOutput = ""
                    let retryStream = provider.streamCompletion(messages: retryMessages, parameters: parameters)
                    for try await chunk in retryStream {
                        if Task.isCancelled { return }
                        retriedOutput += chunk
                    }
                    post = self.postProcessor.process(
                        outputText: retriedOutput,
                        tier: assembled.complexity.tier,
                        maxOutputWords: assembled.complexity.maxOutputWords
                    )
                }

                output = post.cleanedOutput

                guard !output.isEmpty else {
                    Logger.shared.warning("WatchFolderService: Empty response for \(filename)")
                    self.writeErrorFile(
                        folder: folderURL,
                        baseName: baseName,
                        error: "LLM returned an empty response."
                    )
                    return
                }

                // Write optimized file
                let outputURL = folderURL.appendingPathComponent("\(baseName)-optimized.txt")
                try output.write(to: outputURL, atomically: true, encoding: .utf8)

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)

                // Save history entry
                let entry = PromptHistoryEntry(
                    inputText: trimmed,
                    outputText: output,
                    styleID: style.id,
                    providerName: config.selectedProvider.displayName,
                    modelName: config.selectedModelName,
                    durationMilliseconds: duration,
                    sourceType: .watchFolder
                )

                await MainActor.run {
                    self.historyService.save(entry)

                    // Index into context engine
                    self.contextEngine.indexOptimization(
                        inputText: trimmed,
                        outputText: output,
                        promptID: entry.id,
                        entityAnalysis: assembled.entityAnalysis
                    )

                    // Auto-clipboard
                    if config.watchFolderAutoClipboard {
                        _ = self.clipboardService.writeText(output)
                    }
                }

                // Send notification
                let preview = String(output.prefix(80))
                self.sendNotification(filename: filename, preview: preview)

                Logger.shared.info("WatchFolderService: Completed \(filename) in \(duration)ms")

            } catch {
                if Task.isCancelled { return }
                Logger.shared.error("WatchFolderService: Optimization failed for \(filename)", error: error)
                self.writeErrorFile(
                    folder: folderURL,
                    baseName: baseName,
                    error: error.localizedDescription
                )
                self.sendErrorNotification(filename: filename, error: error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func markProcessed(_ filename: String) {
        var current = processedFilenames
        current.insert(filename)
        processedFilenames = current
    }

    private func writeErrorFile(folder: URL, baseName: String, error: String) {
        let errorURL = folder.appendingPathComponent("\(baseName)-error.txt")
        let content = "Optimization failed:\n\n\(error)\n\nTo retry, rename the original file and drop it again."
        do {
            try content.write(to: errorURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.shared.error("WatchFolderService: Failed to write error file", error: error)
        }
    }

    private func sendNotification(filename: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "Watch Folder: Optimized"
        content.body = "\(filename)\n\(preview)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendErrorNotification(filename: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Watch Folder: Error"
        content.body = "\(filename): \(error)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
