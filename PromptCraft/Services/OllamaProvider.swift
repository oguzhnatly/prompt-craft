import Foundation

final class OllamaProvider: LLMProviderProtocol {
    let displayName = "Ollama (Local)"
    let iconName = "desktopcomputer"
    let providerType: LLMProvider = .ollama

    private var baseHost: String {
        let port = ConfigurationService.shared.configuration.ollamaPort
        return "http://localhost:\(port)"
    }

    private let session: URLSession

    /// Maximum characters in a streaming response before truncation.
    private let maxResponseLength = 100_000

    /// Cached registry models (fetched from ollama.com).
    private static var cachedRegistryModels: [OllamaCatalogModel]?
    private static var lastRegistryFetch: Date?
    private static let registryCacheDuration: TimeInterval = 3600 // 1 hour

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Registry: Fetch Latest Models from ollama.com

    /// Fetch popular models from PromptCraft Cloud API first, then ollama.com/library as fallback.
    /// The cloud proxy lets us fix issues server-side without requiring app updates.
    func fetchRegistryModels() async -> [OllamaCatalogModel] {
        // Return cache if fresh
        if let cached = Self.cachedRegistryModels,
           let lastFetch = Self.lastRegistryFetch,
           Date().timeIntervalSince(lastFetch) < Self.registryCacheDuration {
            return cached
        }

        // Attempt 1: PromptCraft Cloud API (JSON, fast, fixable server-side)
        if let models = await fetchFromCloudProxy(), !models.isEmpty {
            Self.cachedRegistryModels = models
            Self.lastRegistryFetch = Date()
            return models
        }

        // Attempt 2: Scrape ollama.com/library directly
        if let models = await fetchFromOllamaWebsite(), !models.isEmpty {
            Self.cachedRegistryModels = models
            Self.lastRegistryFetch = Date()
            return models
        }

        // Attempt 3: Hardcoded fallback
        return Self.cachedRegistryModels ?? Self.fallbackCatalog
    }

    /// Fetch from PromptCraft Cloud proxy API — returns JSON array of models.
    /// Expected response: `{ "models": [{ "name", "displayName", "description", "parameterSize", "availableSizes", "tags", "pullCount" }] }`
    private func fetchFromCloudProxy() async -> [OllamaCatalogModel]? {
        guard let url = URL(string: AppConstants.CloudAPI.ollamaModelsURL) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(CloudOllamaModelsResponse.self, from: data)
            let models = decoded.models.map { m in
                OllamaCatalogModel(
                    name: m.name,
                    displayName: m.displayName,
                    description: m.description,
                    parameterSize: m.parameterSize,
                    availableSizes: m.availableSizes,
                    tags: m.tags,
                    pullCount: m.pullCount
                )
            }
            Logger.shared.info("Ollama: fetched \(models.count) models from cloud proxy")
            return models.isEmpty ? nil : models
        } catch {
            Logger.shared.warning("Ollama: cloud proxy fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Scrape ollama.com/library HTML as fallback.
    private func fetchFromOllamaWebsite() async -> [OllamaCatalogModel]? {
        guard let url = URL(string: "https://ollama.com/library") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }

            let models = Self.parseLibraryHTML(html)
            Logger.shared.info("Ollama: scraped \(models.count) models from ollama.com")
            return models.isEmpty ? nil : models
        } catch {
            Logger.shared.warning("Ollama: website scrape failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Parse the ollama.com/library HTML to extract model data.
    static func parseLibraryHTML(_ html: String) -> [OllamaCatalogModel] {
        var models: [OllamaCatalogModel] = []

        // Split by model card anchors: <a href="/library/MODEL_NAME"
        let cardPattern = #"<a href="/library/([^"]+)" class="group"#
        guard let cardRegex = try? NSRegularExpression(pattern: cardPattern) else { return [] }
        let nsHTML = html as NSString
        let cardMatches = cardRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in cardMatches {
            guard match.numberOfRanges >= 2 else { continue }
            let nameRange = match.range(at: 1)
            let modelName = nsHTML.substring(with: nameRange)

            // Skip embedding models and non-text-generation models
            if modelName.contains("embed") || modelName.contains("nomic") ||
               modelName.contains("mxbai") || modelName.contains("bge") { continue }

            // Get the card HTML (from this match to next card or end)
            let cardStart = match.range.location
            let cardEnd: Int
            if let nextMatch = cardMatches.first(where: { $0.range.location > cardStart }) {
                cardEnd = nextMatch.range.location
            } else {
                cardEnd = min(cardStart + 3000, nsHTML.length)
            }
            let cardHTML = nsHTML.substring(with: NSRange(location: cardStart, length: cardEnd - cardStart))

            // Extract description
            let description = extractBetween(cardHTML, start: #"text-neutral-800 text-md">"#, end: "</p>")
                ?? ""

            // Extract capabilities (tags like "tools", "thinking", "vision", "cloud")
            var tags: [String] = []
            let capPattern = #"x-test-capability[^>]*>([^<]+)<"#
            if let capRegex = try? NSRegularExpression(pattern: capPattern) {
                let capMatches = capRegex.matches(in: cardHTML, range: NSRange(location: 0, length: cardHTML.count))
                for cm in capMatches {
                    if cm.numberOfRanges >= 2 {
                        let tag = (cardHTML as NSString).substring(with: cm.range(at: 1)).trimmingCharacters(in: .whitespaces)
                        if !tag.isEmpty { tags.append(tag) }
                    }
                }
            }

            // Extract sizes
            var sizes: [String] = []
            let sizePattern = #"x-test-size[^>]*>([^<]+)<"#
            if let sizeRegex = try? NSRegularExpression(pattern: sizePattern) {
                let sizeMatches = sizeRegex.matches(in: cardHTML, range: NSRange(location: 0, length: cardHTML.count))
                for sm in sizeMatches {
                    if sm.numberOfRanges >= 2 {
                        let size = (cardHTML as NSString).substring(with: sm.range(at: 1)).trimmingCharacters(in: .whitespaces)
                        if !size.isEmpty { sizes.append(size) }
                    }
                }
            }

            // Extract pull count
            let pullCount = extractBetween(cardHTML, start: #"x-test-pull-count>"#, end: "<")?.trimmingCharacters(in: .whitespaces) ?? ""

            // Pick the best default size for our use case (prefer 7-14B range)
            let preferredSize = Self.pickPreferredSize(sizes)

            // Clean description (remove emoji prefixes)
            var cleanDesc = description.trimmingCharacters(in: .whitespaces)
            // Strip leading emoji
            if let first = cleanDesc.unicodeScalars.first, first.value > 127 {
                cleanDesc = String(cleanDesc.drop(while: { c in
                    c.unicodeScalars.first.map { $0.value > 127 } ?? false || c == " "
                }))
            }

            let catalog = OllamaCatalogModel(
                name: modelName,
                displayName: Self.formatDisplayName(modelName),
                description: String(cleanDesc.prefix(120)),
                parameterSize: preferredSize,
                availableSizes: sizes,
                tags: tags,
                pullCount: pullCount
            )
            models.append(catalog)
        }

        return models
    }

    /// Pick the best parameter size for prompt optimization (prefer 7-14B).
    private static func pickPreferredSize(_ sizes: [String]) -> String? {
        guard !sizes.isEmpty else { return nil }
        // Preferred order: 8b, 7b, 14b, 12b, 3b, others
        let preferred = ["8b", "7b", "14b", "12b", "4b", "3b", "9b", "1b"]
        for p in preferred {
            if sizes.contains(where: { $0.lowercased() == p }) { return p.uppercased() }
        }
        return sizes.first?.uppercased()
    }

    /// Format model name for display.
    private static func formatDisplayName(_ name: String) -> String {
        let parts = name.split(separator: "-").map { part -> String in
            let s = String(part)
            // Capitalize model names nicely
            if s.allSatisfy({ $0.isNumber || $0 == "." }) { return s }
            return s.prefix(1).uppercased() + s.dropFirst()
        }
        return parts.joined(separator: " ")
            .replacingOccurrences(of: "Llama", with: "Llama")
            .replacingOccurrences(of: "Deepseek", with: "DeepSeek")
    }

    /// Extract text between two markers in a string.
    private static func extractBetween(_ str: String, start: String, end: String) -> String? {
        guard let startRange = str.range(of: start) else { return nil }
        let after = str[startRange.upperBound...]
        guard let endRange = after.range(of: end) else { return nil }
        return String(after[..<endRange.lowerBound])
    }

    // MARK: - Fallback Catalog (used when network unavailable)

    /// Hardcoded fallback used only when ollama.com is unreachable.
    static let fallbackCatalog: [OllamaCatalogModel] = [
        OllamaCatalogModel(name: "qwen3", displayName: "Qwen 3", description: "Latest generation with dense and mixture-of-experts configurations.", parameterSize: "8B", availableSizes: ["0.6b", "1.7b", "4b", "8b", "14b", "30b", "32b", "235b"], tags: ["thinking", "tools"], pullCount: "19.2M"),
        OllamaCatalogModel(name: "llama3.1", displayName: "Llama 3.1", description: "State-of-the-art model from Meta available in 8B, 70B and 405B parameter sizes.", parameterSize: "8B", availableSizes: ["8b", "70b", "405b"], tags: ["tools"], pullCount: "110.2M"),
        OllamaCatalogModel(name: "deepseek-r1", displayName: "DeepSeek R1", description: "Open reasoning model with performance approaching leading proprietary systems.", parameterSize: "8B", availableSizes: ["1.5b", "7b", "8b", "14b", "32b", "70b", "671b"], tags: ["thinking"], pullCount: "78.1M"),
        OllamaCatalogModel(name: "gemma3", displayName: "Gemma 3", description: "Capable single-GPU models from Google.", parameterSize: "12B", availableSizes: ["1b", "4b", "12b", "27b"], tags: ["vision", "tools"], pullCount: "31.8M"),
        OllamaCatalogModel(name: "phi4", displayName: "Phi 4", description: "State-of-the-art open model from Microsoft.", parameterSize: "14B", availableSizes: ["14b"], tags: ["tools"], pullCount: "7.2M"),
        OllamaCatalogModel(name: "mistral", displayName: "Mistral", description: "The 7B model released by Mistral AI, updated to version 0.3.", parameterSize: "7B", availableSizes: ["7b"], tags: [], pullCount: "25.2M"),
        OllamaCatalogModel(name: "llama3.2", displayName: "Llama 3.2", description: "Meta's lightweight models optimized for compact deployment.", parameterSize: "3B", availableSizes: ["1b", "3b"], tags: [], pullCount: "57.1M"),
        OllamaCatalogModel(name: "qwen2.5", displayName: "Qwen 2.5", description: "Models pretrained on extensive datasets supporting 128K tokens.", parameterSize: "7B", availableSizes: ["0.5b", "1.5b", "3b", "7b", "14b", "32b", "72b"], tags: ["tools"], pullCount: "21.3M"),
        OllamaCatalogModel(name: "gemma2", displayName: "Gemma 2", description: "High-performing efficient models from Google.", parameterSize: "9B", availableSizes: ["2b", "9b", "27b"], tags: [], pullCount: "15.8M"),
        OllamaCatalogModel(name: "llama3.3", displayName: "Llama 3.3", description: "Offers similar performance to Llama 3.1 405B.", parameterSize: "70B", availableSizes: ["70b"], tags: ["tools"], pullCount: "3.3M"),
    ]

    // MARK: - Best-For Labels

    /// Determine what a model is best suited for based on its tags and name.
    static func bestForLabel(name: String, tags: [String]) -> String? {
        let n = name.lowercased()
        let t = Set(tags.map { $0.lowercased() })

        if t.contains("thinking") && t.contains("tools") { return "Best all-rounder" }
        if t.contains("thinking") { return "Reasoning & analysis" }
        if n.contains("coder") || n.contains("codestral") || n.contains("devstral") { return "Code generation" }
        if t.contains("vision") && t.contains("tools") { return "Vision & tools" }
        if t.contains("vision") { return "Vision & multimodal" }
        if t.contains("tools") && n.contains("gemma") { return "Fast & capable" }
        if t.contains("tools") { return "General purpose" }
        if n.contains("phi") { return "Reasoning & STEM" }
        if n.contains("mistral") || n.contains("ministral") { return "Lightweight & fast" }
        if n.contains("llama3.2") { return "Compact & efficient" }
        if n.contains("llama3.3") || n.contains("405b") { return "Maximum quality" }
        if n.contains("qwen2.5") { return "Multilingual" }
        return nil
    }

    /// Determine if a model should be recommended for prompt optimization.
    static func isRecommendedModel(_ name: String, tags: [String]) -> Bool {
        let n = name.lowercased()
        let t = Set(tags.map { $0.lowercased() })
        // Recommend models good at reasoning + instruction following
        if n == "qwen3" && t.contains("thinking") { return true }
        if n == "llama3.1" { return true }
        if n == "deepseek-r1" && t.contains("thinking") { return true }
        return false
    }

    // MARK: - Available Models (merged installed + registry)

    func availableModels() async throws -> [LLMModelInfo] {
        // Fetch installed and registry in parallel
        async let installedTask = fetchInstalledModels()
        async let registryTask = fetchRegistryModels()

        let installed = (try? await installedTask) ?? []
        let registry = await registryTask

        return mergedModelList(installed: installed, registry: registry)
    }

    /// Fetch only locally installed models from Ollama.
    func fetchInstalledModels() async throws -> [String] {
        guard let url = URL(string: "\(baseHost)/api/tags") else {
            throw LLMError.unknown(message: "Invalid Ollama URL")
        }

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.unknown(message: "Invalid response from Ollama")
            }

            guard httpResponse.statusCode == 200 else {
                throw LLMError.unknown(message: "Ollama is not running. Start it with `ollama serve`.")
            }

            let result = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return result.models.map(\.name)
        } catch let error as LLMError {
            throw error
        } catch let urlError as URLError where urlError.code == .cannotConnectToHost
            || urlError.code == .networkConnectionLost
            || urlError.code == .timedOut {
            throw LLMError.unknown(message: "Cannot connect to Ollama at \(baseHost). Is it running? Start with `ollama serve`.")
        } catch {
            throw LLMError.networkError(underlying: error)
        }
    }

    /// Merge installed models with the registry catalog.
    func mergedModelList(installed: [String], registry: [OllamaCatalogModel]) -> [LLMModelInfo] {
        let normalizedInstalled = Set(installed.map { Self.normalizeModelName($0) })

        var result: [LLMModelInfo] = []
        var addedNames: Set<String> = []

        // 1. Installed models that match registry entries (with rich metadata)
        for catalogModel in registry {
            let normalized = Self.normalizeModelName(catalogModel.name)
            if normalizedInstalled.contains(normalized) {
                let installedName = installed.first { Self.normalizeModelName($0) == normalized } ?? catalogModel.name
                result.append(LLMModelInfo(
                    id: installedName,
                    displayName: catalogModel.displayName,
                    contextWindow: 8_192,
                    isDefault: result.isEmpty,
                    tags: catalogModel.tags,
                    parameterSize: catalogModel.parameterSize,
                    isInstalled: true,
                    isRecommended: Self.isRecommendedModel(catalogModel.name, tags: catalogModel.tags),
                    bestFor: Self.bestForLabel(name: catalogModel.name, tags: catalogModel.tags)
                ))
                addedNames.insert(normalized)
            }
        }

        // 2. Installed models NOT in registry (custom/user-pulled)
        for name in installed {
            let normalized = Self.normalizeModelName(name)
            if !addedNames.contains(normalized) {
                result.append(LLMModelInfo(
                    id: name,
                    displayName: name,
                    contextWindow: 8_192,
                    isDefault: result.isEmpty,
                    tags: [],
                    parameterSize: nil,
                    isInstalled: true,
                    isRecommended: false,
                    bestFor: nil
                ))
                addedNames.insert(normalized)
            }
        }

        // 3. Registry models NOT yet installed (top models available for download)
        // Limit to top 15 to keep the list manageable
        var downloadCount = 0
        for catalogModel in registry {
            guard downloadCount < 15 else { break }
            let normalized = Self.normalizeModelName(catalogModel.name)
            if !addedNames.contains(normalized) {
                result.append(LLMModelInfo(
                    id: catalogModel.name,
                    displayName: catalogModel.displayName,
                    contextWindow: 8_192,
                    isDefault: false,
                    tags: catalogModel.tags,
                    parameterSize: catalogModel.parameterSize,
                    isInstalled: false,
                    isRecommended: Self.isRecommendedModel(catalogModel.name, tags: catalogModel.tags),
                    bestFor: Self.bestForLabel(name: catalogModel.name, tags: catalogModel.tags)
                ))
                addedNames.insert(normalized)
                downloadCount += 1
            }
        }

        return result
    }

    /// Strip `:latest` and normalize model name for comparison.
    static func normalizeModelName(_ name: String) -> String {
        var n = name.lowercased().trimmingCharacters(in: .whitespaces)
        if n.hasSuffix(":latest") {
            n = String(n.dropLast(7))
        }
        return n
    }

    // MARK: - Pull / Download Model

    /// Pull (download) a model from the Ollama registry. Returns an AsyncThrowingStream of progress updates.
    func pullModel(name: String) -> AsyncThrowingStream<OllamaPullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "\(baseHost)/api/pull") else {
                        throw LLMError.unknown(message: "Invalid Ollama URL")
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.timeoutInterval = 3600 // Models can be large
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "stream": true])

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw LLMError.unknown(message: "Failed to start model download.")
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
                        if let progress = try? JSONDecoder().decode(OllamaPullResponse.self, from: data) {
                            let p = OllamaPullProgress(
                                status: progress.status ?? "",
                                total: progress.total ?? 0,
                                completed: progress.completed ?? 0
                            )
                            continuation.yield(p)
                            if progress.status == "success" { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Delete Model

    /// Delete a locally installed model via Ollama's API.
    func deleteModel(name: String) async throws {
        guard let url = URL(string: "\(baseHost)/api/delete") else {
            throw LLMError.unknown(message: "Invalid Ollama URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.unknown(message: "Invalid response from Ollama")
        }
        guard httpResponse.statusCode == 200 else {
            throw LLMError.unknown(message: "Failed to delete model '\(name)'. Status: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Validate (check connectivity)

    func validateAPIKey(_ key: String) async throws -> Bool {
        guard let url = URL(string: "\(baseHost)/api/tags") else {
            throw LLMError.unknown(message: "Invalid Ollama URL")
        }

        do {
            let (_, response) = try await session.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw LLMError.unknown(message: "Ollama is not running.")
            }
            return true
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.unknown(message: "Cannot connect to Ollama at \(baseHost). Is it running? Start with `ollama serve`.")
        }
    }

    // MARK: - Streaming

    func streamCompletion(
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var totalLength = 0
                var insideThinkBlock = false  // Track <think> blocks to strip them
                do {
                    guard let tagsURL = URL(string: "\(baseHost)/api/tags") else {
                        throw LLMError.unknown(message: "Invalid Ollama URL")
                    }

                    Logger.shared.info("Ollama: checking connectivity")

                    do {
                        let (_, tagsResponse) = try await self.session.data(for: URLRequest(url: tagsURL))
                        guard let tagsHTTP = tagsResponse as? HTTPURLResponse, tagsHTTP.statusCode == 200 else {
                            throw LLMError.unknown(message: "Ollama is not running. Start it with `ollama serve`.")
                        }
                    } catch let urlError as URLError where urlError.code == .cannotConnectToHost
                        || urlError.code == .networkConnectionLost
                        || urlError.code == .timedOut {
                        throw LLMError.unknown(message: "Cannot connect to Ollama at \(self.baseHost). Is it running? Start with `ollama serve`.")
                    }

                    Logger.shared.info("Ollama: starting stream for model \(parameters.model)")

                    let request = try self.buildStreamRequest(messages: messages, parameters: parameters)
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.unknown(message: "Invalid response from Ollama")
                    }

                    guard httpResponse.statusCode == 200 else {
                        if httpResponse.statusCode == 404 {
                            throw LLMError.modelUnavailable
                        }
                        throw LLMError.serverError(statusCode: httpResponse.statusCode, message: "Ollama error")
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard !line.isEmpty else { continue }
                        guard let data = line.data(using: .utf8) else { continue }

                        guard let chunk = try? JSONDecoder().decode(OllamaChatChunk.self, from: data) else {
                            Logger.shared.warning("Ollama: skipped malformed chunk")
                            continue
                        }

                        if let content = chunk.message?.content, !content.isEmpty {
                            // Strip <think>...</think> blocks from thinking models
                            var filtered = content
                            if filtered.contains("<think>") { insideThinkBlock = true }
                            if insideThinkBlock {
                                if let endRange = filtered.range(of: "</think>") {
                                    filtered = String(filtered[endRange.upperBound...])
                                    insideThinkBlock = false
                                } else {
                                    // Still inside think block — skip entirely
                                    continue
                                }
                            }
                            // Handle opening tag mid-chunk
                            if let startRange = filtered.range(of: "<think>") {
                                filtered = String(filtered[..<startRange.lowerBound])
                                insideThinkBlock = true
                            }

                            guard !filtered.isEmpty else { continue }
                            totalLength += filtered.count
                            if totalLength > self.maxResponseLength {
                                Logger.shared.warning("Ollama: response exceeded \(self.maxResponseLength) chars, truncating")
                                continuation.finish(throwing: LLMError.responseTooLong(truncatedOutput: ""))
                                return
                            }
                            continuation.yield(filtered)
                        }
                        if chunk.done == true { break }
                    }

                    Logger.shared.info("Ollama: stream completed (\(totalLength) chars)")
                    continuation.finish()
                } catch is CancellationError {
                    Logger.shared.info("Ollama: stream cancelled")
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    Logger.shared.error("Ollama: stream error", error: error)
                    continuation.finish(throwing: error)
                } catch let urlError as URLError where urlError.code == .cannotConnectToHost
                    || urlError.code == .networkConnectionLost {
                    Logger.shared.error("Ollama: connection lost", error: urlError)
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.unknown(message: "Cannot connect to Ollama at \(self.baseHost). Is it running? Start with `ollama serve`."))
                    }
                } catch {
                    Logger.shared.error("Ollama: unexpected error", error: error)
                    if totalLength > 0 {
                        continuation.finish(throwing: LLMError.partialResponse(partialOutput: ""))
                    } else {
                        continuation.finish(throwing: LLMError.networkError(underlying: error))
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Helpers

    private func buildStreamRequest(
        messages: [LLMMessage],
        parameters: LLMRequestParameters
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseHost)/api/chat") else {
            throw LLMError.unknown(message: "Invalid Ollama URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let chatMessages = messages.map { msg -> [String: String] in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        let body: [String: Any] = [
            "model": parameters.model,
            "messages": chatMessages,
            "stream": true,
            "think": false,  // Disable chain-of-thought reasoning for speed
            "options": [
                "temperature": parameters.temperature,
                "num_predict": parameters.maxTokens,
            ] as [String: Any],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Catalog Model

struct OllamaCatalogModel {
    let name: String
    let displayName: String
    let description: String
    let parameterSize: String?
    let availableSizes: [String]
    let tags: [String]
    let pullCount: String
}

// MARK: - Pull Progress

struct OllamaPullProgress {
    let status: String
    let total: Int64
    let completed: Int64

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var isDownloading: Bool {
        status.contains("pulling") || status.contains("downloading")
    }
}

// MARK: - Response Types

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]

    struct OllamaModel: Decodable {
        let name: String
    }
}

private struct OllamaChatChunk: Decodable {
    let message: Message?
    let done: Bool?

    struct Message: Decodable {
        let content: String?
    }
}

private struct OllamaPullResponse: Decodable {
    let status: String?
    let total: Int64?
    let completed: Int64?
}

// MARK: - Cloud Proxy Response

private struct CloudOllamaModelsResponse: Decodable {
    let models: [CloudOllamaModel]

    struct CloudOllamaModel: Decodable {
        let name: String
        let displayName: String
        let description: String
        let parameterSize: String?
        let availableSizes: [String]
        let tags: [String]
        let pullCount: String
    }
}
