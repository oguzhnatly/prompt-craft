import Foundation

/// Simple file-based logger with rotation.
/// Writes to ~/Library/Logs/PromptCraft/promptcraft.log.
/// Never logs API keys or full prompt text.
final class Logger {
    static let shared = Logger()

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let fileManager = FileManager.default
    private let maxFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    private let maxFiles = 5
    private let queue = DispatchQueue(label: "com.promptcraft.logger", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    private var logDirectoryURL: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/PromptCraft")
    }

    private var currentLogFileURL: URL {
        logDirectoryURL.appendingPathComponent("promptcraft.log")
    }

    private init() {
        ensureLogDirectoryExists()
    }

    // MARK: - Public API

    func debug(_ message: String, file: String = #fileID, function: String = #function) {
        #if DEBUG
        log(.debug, message, file: file, function: function)
        #endif
    }

    func info(_ message: String, file: String = #fileID, function: String = #function) {
        log(.info, message, file: file, function: function)
    }

    func warning(_ message: String, error: Error? = nil, file: String = #fileID, function: String = #function) {
        var msg = message
        if let error {
            msg += " | \(String(describing: type(of: error))): \(error.localizedDescription)"
        }
        log(.warning, msg, file: file, function: function)
    }

    func error(_ message: String, error: Error? = nil, file: String = #fileID, function: String = #function) {
        var msg = message
        if let error {
            msg += " | \(String(describing: type(of: error))): \(error.localizedDescription)"
        }
        log(.error, msg, file: file, function: function)
    }

    /// Returns the most recent log content (up to ~100KB) for bug reporting.
    func recentLogs() -> String {
        let url = currentLogFileURL
        guard fileManager.fileExists(atPath: url.path) else { return "(No logs available)" }

        do {
            let data = try Data(contentsOf: url)
            let full = String(data: data, encoding: .utf8) ?? "(Could not read log)"
            // Return last ~100KB
            let maxChars = 100_000
            if full.count > maxChars {
                return String(full.suffix(maxChars))
            }
            return full
        } catch {
            return "(Error reading logs: \(error.localizedDescription))"
        }
    }

    // MARK: - Private

    private func log(_ level: Level, _ message: String, file: String, function: String) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let entry = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(function)] \(message)\n"

        queue.async { [weak self] in
            self?.writeEntry(entry)
        }
    }

    private func writeEntry(_ entry: String) {
        let url = currentLogFileURL

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        // Check size and rotate if needed
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64, size >= maxFileSize {
            rotate()
        }

        guard let data = entry.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

    private func rotate() {
        // Delete oldest log if at max
        let oldestURL = logDirectoryURL.appendingPathComponent("promptcraft.\(maxFiles - 1).log")
        try? fileManager.removeItem(at: oldestURL)

        // Shift existing rotated logs
        for i in stride(from: maxFiles - 2, through: 1, by: -1) {
            let src = logDirectoryURL.appendingPathComponent("promptcraft.\(i).log")
            let dst = logDirectoryURL.appendingPathComponent("promptcraft.\(i + 1).log")
            if fileManager.fileExists(atPath: src.path) {
                try? fileManager.moveItem(at: src, to: dst)
            }
        }

        // Move current to .1
        let rotatedURL = logDirectoryURL.appendingPathComponent("promptcraft.1.log")
        try? fileManager.moveItem(at: currentLogFileURL, to: rotatedURL)

        // Create fresh file
        fileManager.createFile(atPath: currentLogFileURL.path, contents: nil)
    }

    private func ensureLogDirectoryExists() {
        if !fileManager.fileExists(atPath: logDirectoryURL.path) {
            try? fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        }
    }
}
