import Combine
import Foundation
import Network
import Security

final class LocalAPIService: ObservableObject {
    static let shared = LocalAPIService()

    @Published private(set) var isRunning: Bool = false

    private let configService = ConfigurationService.shared
    private let keychainService = KeychainService.shared
    private let styleService = StyleService.shared
    private let providerManager = LLMProviderManager.shared
    private let promptAssembler = PromptAssembler.shared
    private let postProcessor = PostProcessor.shared
    private let historyService = HistoryService.shared
    private let contextEngine = ContextEngineService.shared
    private let licensingService = LicensingService.shared

    private var listener: NWListener?
    private var cancellables = Set<AnyCancellable>()

    private static let tokenKeychainAccount = "localAPIToken"

    // MARK: - Rate Limiting

    private let rateLimitQueue = DispatchQueue(label: "com.promptcraft.localAPI.rateLimit")
    private var requestTimestamps: [Date] = []
    private let rateLimitWindow: TimeInterval = 60
    private let rateLimitMax: Int = 10

    // MARK: - Lifecycle

    private init() {
        observeConfigChanges()
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    func startIfEnabled() {
        let config = configService.configuration
        if config.localAPIEnabled {
            start()
        }
    }

    func getOrCreateToken() -> String {
        if let existing = keychainService.getGenericSecret(account: Self.tokenKeychainAccount) {
            return existing
        }
        return regenerateToken()
    }

    @discardableResult
    func regenerateToken() -> String {
        let token = Self.generateToken()
        keychainService.saveGenericSecret(account: Self.tokenKeychainAccount, value: token)
        Logger.shared.info("LocalAPIService: Token regenerated")
        return token
    }

    // MARK: - Configuration Observation

    private struct LocalAPIKey: Equatable {
        let enabled: Bool
        let port: Int
    }

    private func observeConfigChanges() {
        configService.$configuration
            .map { LocalAPIKey(enabled: $0.localAPIEnabled, port: $0.localAPIPort) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] key in
                guard let self else { return }
                if key.enabled {
                    self.stop()
                    self.start()
                } else {
                    self.stop()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Start / Stop

    private func start() {
        guard !isRunning else { return }

        let config = configService.configuration
        let port = UInt16(config.localAPIPort)

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            Logger.shared.error("LocalAPIService: Invalid port \(config.localAPIPort)")
            return
        }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)

        do {
            listener = try NWListener(using: parameters)
        } catch {
            Logger.shared.error("LocalAPIService: Failed to create listener", error: error)
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.shared.info("LocalAPIService: Listening on port \(port)")
                DispatchQueue.main.async { self?.isRunning = true }
            case .failed(let error):
                Logger.shared.error("LocalAPIService: Listener failed — \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.listener = nil
                }
            case .cancelled:
                DispatchQueue.main.async { self?.isRunning = false }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
        }
        Logger.shared.info("LocalAPIService: Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                Logger.shared.warning("LocalAPIService: Connection error — \(error.localizedDescription)")
                connection.cancel()
                return
            }

            guard let data, let raw = String(data: data, encoding: .utf8) else {
                self.sendResponse(connection: connection, status: 400, statusText: "Bad Request", body: ["error": "Invalid request data."])
                return
            }

            let request = self.parseHTTPRequest(raw)
            self.routeRequest(request, connection: connection)
        }
    }

    // MARK: - HTTP Parsing

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data?
    }

    private func parseHTTPRequest(_ raw: String) -> HTTPRequest {
        let headerBodySplit = raw.components(separatedBy: "\r\n\r\n")
        let headerSection = headerBodySplit[0]
        let bodyString = headerBodySplit.count > 1 ? headerBodySplit.dropFirst().joined(separator: "\r\n\r\n") : nil

        let lines = headerSection.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ", maxSplits: 2)

        let method = parts.count > 0 ? String(parts[0]) : "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        let body = bodyString?.data(using: .utf8)

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    // MARK: - Routing

    private func routeRequest(_ request: HTTPRequest, connection: NWConnection) {
        // CORS preflight
        if request.method == "OPTIONS" {
            sendResponse(connection: connection, status: 204, statusText: "No Content", body: nil, extraHeaders: corsHeaders())
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/health"):
            handleHealth(connection: connection)

        case ("POST", "/optimize"):
            guard authenticateRequest(request, connection: connection) else { return }
            guard checkRateLimit(connection: connection) else { return }
            handleOptimize(request: request, connection: connection)

        case ("GET", "/styles"):
            guard authenticateRequest(request, connection: connection) else { return }
            handleStyles(connection: connection)

        default:
            sendResponse(connection: connection, status: 404, statusText: "Not Found", body: ["error": "Unknown endpoint."])
        }
    }

    // MARK: - Endpoint Handlers

    private func handleHealth(connection: NWConnection) {
        sendResponse(connection: connection, status: 200, statusText: "OK", body: ["status": "ok", "version": "1.0"])
    }

    private func handleStyles(connection: NWConnection) {
        let config = configService.configuration
        let enabledStyles = config.enabledStyleIDs.compactMap { styleService.getByIdIncludingInternal($0) }

        let stylesJSON: [[String: Any]] = enabledStyles.map { style in
            [
                "id": style.id.uuidString,
                "name": style.displayName,
                "description": style.shortDescription,
                "category": style.category.rawValue,
                "icon": style.iconName,
            ]
        }

        sendResponse(connection: connection, status: 200, statusText: "OK", body: ["styles": stylesJSON])
    }

    private func handleOptimize(request: HTTPRequest, connection: NWConnection) {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let text = json["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendResponse(connection: connection, status: 400, statusText: "Bad Request", body: ["error": "Missing or empty 'text' field."])
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedStyleId = (json["styleId"] as? String).flatMap(UUID.init)
        let verbosityString = json["verbosity"] as? String

        let verbosity: OutputVerbosity
        switch verbosityString {
        case "concise": verbosity = .concise
        case "balanced": verbosity = .balanced
        case "detailed": verbosity = .detailed
        default: verbosity = configService.configuration.outputVerbosity
        }

        let config = configService.configuration

        // Resolve style
        let styleID = requestedStyleId
            ?? config.enabledStyleIDs.first
            ?? DefaultStyles.defaultStyleID
        guard let style = styleService.getByIdIncludingInternal(styleID) else {
            sendResponse(connection: connection, status: 400, statusText: "Bad Request", body: ["error": "Style not found for ID \(styleID.uuidString)."])
            return
        }

        // Check API key
        if config.selectedProvider != .ollama && config.selectedProvider != .promptCraftCloud {
            guard keychainService.hasAPIKey(for: config.selectedProvider) else {
                sendResponse(connection: connection, status: 401, statusText: "Unauthorized", body: ["error": "No API key configured for \(config.selectedProvider.displayName)."])
                return
            }
        }

        let provider = providerManager.activeProvider
        let startTime = Date()

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                let assembled = await self.promptAssembler.assemble(
                    rawInput: trimmed,
                    style: style,
                    providerType: config.selectedProvider,
                    verbosity: verbosity
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
                    self.sendResponse(connection: connection, status: 502, statusText: "Bad Gateway", body: ["error": "LLM returned an empty response."])
                    return
                }

                let duration = Int(Date().timeIntervalSince(startTime) * 1000)

                // Save history entry
                let entry = PromptHistoryEntry(
                    inputText: trimmed,
                    outputText: output,
                    styleID: style.id,
                    providerName: config.selectedProvider.displayName,
                    modelName: config.selectedModelName,
                    durationMilliseconds: duration,
                    sourceType: .api
                )

                await MainActor.run {
                    self.historyService.save(entry)
                    self.contextEngine.indexOptimization(
                        inputText: trimmed,
                        outputText: output,
                        promptID: entry.id,
                        entityAnalysis: assembled.entityAnalysis
                    )
                }

                let responseBody: [String: Any] = [
                    "output": output,
                    "tier": assembled.complexity.tier.rawValue,
                    "tokens": assembled.estimatedTokenCount,
                    "durationMs": duration,
                    "style": style.displayName,
                    "provider": config.selectedProvider.displayName,
                    "model": config.selectedModelName,
                ]

                self.sendResponse(connection: connection, status: 200, statusText: "OK", body: responseBody)

                Logger.shared.info("LocalAPIService: Optimized in \(duration)ms")

            } catch {
                let (status, statusText) = self.mapLLMError(error)
                self.sendResponse(connection: connection, status: status, statusText: statusText, body: ["error": error.localizedDescription])
            }
        }
    }

    // MARK: - Authentication

    private func authenticateRequest(_ request: HTTPRequest, connection: NWConnection) -> Bool {
        guard let authHeader = request.headers["authorization"],
              authHeader.lowercased().hasPrefix("bearer ") else {
            sendResponse(connection: connection, status: 401, statusText: "Unauthorized", body: ["error": "Invalid or missing bearer token."])
            return false
        }

        let provided = String(authHeader.dropFirst("bearer ".count))
        let stored = getOrCreateToken()

        guard constantTimeCompare(provided, stored) else {
            sendResponse(connection: connection, status: 401, statusText: "Unauthorized", body: ["error": "Invalid or missing bearer token."])
            return false
        }

        return true
    }

    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)

        guard aBytes.count == bBytes.count else { return false }

        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }

    // MARK: - Rate Limiting

    private func checkRateLimit(connection: NWConnection) -> Bool {
        let now = Date()
        let allowed: Bool = rateLimitQueue.sync {
            requestTimestamps.removeAll { now.timeIntervalSince($0) > rateLimitWindow }
            if requestTimestamps.count >= rateLimitMax {
                return false
            }
            requestTimestamps.append(now)
            return true
        }

        if !allowed {
            sendResponse(connection: connection, status: 429, statusText: "Too Many Requests", body: ["error": "Rate limit exceeded. Max \(rateLimitMax) requests per \(Int(rateLimitWindow))s."])
            return false
        }

        return true
    }

    // MARK: - Error Mapping

    private func mapLLMError(_ error: Error) -> (Int, String) {
        guard let llmError = error as? LLMError else {
            return (502, "Bad Gateway")
        }

        switch llmError {
        case .invalidAPIKey, .noAPIKey:
            return (401, "Unauthorized")
        case .rateLimited:
            return (429, "Too Many Requests")
        case .timeout:
            return (504, "Gateway Timeout")
        case .noNetwork, .dnsFailure, .sslError:
            return (503, "Service Unavailable")
        case .serviceUnavailable:
            return (503, "Service Unavailable")
        default:
            return (502, "Bad Gateway")
        }
    }

    // MARK: - HTTP Response

    private func corsHeaders() -> [String: String] {
        [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Authorization, Content-Type",
        ]
    }

    private func sendResponse(connection: NWConnection, status: Int, statusText: String, body: [String: Any]?, extraHeaders: [String: String] = [:]) {
        var headers: [String: String] = [
            "Content-Type": "application/json; charset=utf-8",
            "Access-Control-Allow-Origin": "*",
        ]
        for (key, value) in extraHeaders {
            headers[key] = value
        }

        let bodyData: Data
        if let body {
            bodyData = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        } else {
            bodyData = Data()
        }

        headers["Content-Length"] = "\(bodyData.count)"

        var responseString = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            responseString += "\(key): \(value)\r\n"
        }
        responseString += "\r\n"

        var responseData = Data(responseString.utf8)
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Token Generation

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fallback to UUID-based token
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
