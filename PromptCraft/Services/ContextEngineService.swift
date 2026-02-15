import Accelerate
import Combine
import Foundation
import NaturalLanguage
import SQLite3

// MARK: - ContextEngineService

final class ContextEngineService: ObservableObject {
    static let shared = ContextEngineService()

    @Published var entryCount: Int = 0
    @Published var clusters: [ProjectCluster] = []
    @Published var isAvailable: Bool = false
    @Published var averageOutputEfficiency: Double?
    @Published var showUpgradeNotice: Bool = false

    private var store: SQLiteStore?
    private let embeddingEngine = EmbeddingEngine()
    private let clusterEngine = ClusterEngine()
    private let entityExtractor = EntityExtractor.shared
    private let configService = ConfigurationService.shared
    private var cancellables = Set<AnyCancellable>()
    private var indexedSinceLastCluster: Int = 0
    private let reclusterThreshold = 10

    /// Approximate characters per token for budget estimation.
    private let charsPerToken: Double = 4.0

    private init() {
        do {
            let newStore = try SQLiteStore()
            store = newStore
            isAvailable = embeddingEngine.isAvailable
            if isAvailable {
                refreshCounts()
            }
            if newStore.didMigrateFromOldSchema {
                DispatchQueue.main.async {
                    self.showUpgradeNotice = true
                }
                Logger.shared.info("ContextEngineService: Migrated from old schema — context database rebuilt fresh.")
            }
        } catch {
            Logger.shared.error("ContextEngineService: Failed to initialize SQLite store", error: error)
            store = nil
            isAvailable = false
        }
    }

    // MARK: - Public API

    /// Index an optimization (input + output) for future context retrieval.
    func indexOptimization(
        inputText: String,
        outputText: String,
        promptID: UUID,
        entityAnalysis: EntityAnalysis? = nil
    ) {
        guard isAvailable, configService.configuration.contextEngineEnabled, let store else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let filteredInput = self.applyStopPhraseFilter(to: inputText)
            let entities = entityAnalysis ?? self.entityExtractor.analyze(filteredInput)

            // Embed only the filtered raw user input text.
            guard let embedding = self.embeddingEngine.embed(filteredInput) else { return }

            let tokenCount = max(1, Int(ceil(Double(filteredInput.count) / self.charsPerToken)))

            let entry = ContextEntry(
                text: filteredInput,
                outputText: outputText,
                embedding: embedding,
                persons: entities.persons,
                projects: entities.projects,
                environments: entities.environments,
                technicalTerms: entities.technicalTerms,
                sourceType: .optimization,
                sourcePromptID: promptID,
                tokenCount: tokenCount
            )

            do {
                try store.insertEntry(entry)

                // Enforce max entries
                let maxEntries = self.configService.configuration.contextMaxEntries
                try store.trimEntries(to: maxEntries)

                await MainActor.run {
                    self.refreshCounts()
                    self.indexedSinceLastCluster += 1
                    if self.indexedSinceLastCluster >= self.reclusterThreshold {
                        self.recluster()
                    }
                }
            } catch {
                Logger.shared.error("ContextEngineService: Failed to index optimization", error: error)
            }
        }
    }

    /// Retrieve relevant context for a query text, respecting a token budget.
    func retrieveContext(for queryText: String, maxTokenBudget: Int = 500) async -> (contextBlock: String?, matchedEntries: [ContextSearchResult]) {
        let matches = await similarityResults(for: queryText)
        guard !matches.isEmpty else { return (nil, []) }

        let selected = selectEntriesWithinBudget(matches, maxTokenBudget: maxTokenBudget)
        guard !selected.isEmpty else { return (nil, []) }

        if let store {
            for result in selected {
                try? store.updateAccess(entryID: result.entry.id)
            }
        }

        let contextBlock = buildContextBlock(from: selected)
        return (contextBlock, selected)
    }

    /// RMPA entry point for context retrieval by raw input.
    func getContext(rawInput: String, maxTokenBudget: Int = 500) async -> (contextBlock: String?, matchedEntries: [ContextSearchResult]) {
        await retrieveContext(for: rawInput, maxTokenBudget: maxTokenBudget)
    }

    /// Returns sorted similarity results without constructing the context block.
    func similarityResults(for queryText: String) async -> [ContextSearchResult] {
        guard isAvailable, configService.configuration.contextEngineEnabled, let store else {
            return []
        }

        let filteredQuery = applyStopPhraseFilter(to: queryText)
        guard let queryEmbedding = embeddingEngine.embed(filteredQuery) else {
            return []
        }

        do {
            let allEntries = try store.allEntries()
            guard !allEntries.isEmpty else { return [] }

            let threshold = configService.configuration.contextRelevanceThreshold
            let now = Date()

            var results: [ContextSearchResult] = []
            for entry in allEntries {
                let similarity = ClusterEngine.cosineSimilarity(queryEmbedding, entry.embedding)
                guard similarity >= threshold else { continue }

                let boosted = boostScore(similarity: similarity, entry: entry, now: now)
                results.append(ContextSearchResult(
                    id: entry.id,
                    entry: entry,
                    similarity: similarity,
                    boostedScore: boosted
                ))
            }

            results.sort { $0.boostedScore > $1.boostedScore }
            return results
        } catch {
            Logger.shared.error("ContextEngineService: Failed to compute similarity results", error: error)
            return []
        }
    }

    /// Build XML context block from precomputed matches.
    func buildContextBlock(from matches: [ContextSearchResult], maxEntries: Int = 5, maxTokenBudget: Int = 500) -> String? {
        guard !matches.isEmpty else { return nil }
        let limited = Array(matches.prefix(maxEntries))
        let budgeted = selectEntriesWithinBudget(limited, maxTokenBudget: maxTokenBudget)
        guard !budgeted.isEmpty else { return nil }
        return buildContextXML(entries: budgeted, now: Date())
    }

    /// Trigger DBSCAN reclustering of all entries.
    func recluster() {
        guard isAvailable, let store else { return }
        indexedSinceLastCluster = 0

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            do {
                let entries = try store.allEntries()
                guard entries.count >= 3 else { return }

                let embeddings = entries.map(\.embedding)
                let ids = entries.map(\.id)
                let assignments = self.clusterEngine.dbscan(embeddings: embeddings, ids: ids)

                // Group by cluster
                var clusterGroups: [Int: [UUID]] = [:]
                for (id, clusterID) in assignments {
                    guard clusterID >= 0 else { continue } // Skip noise
                    clusterGroups[clusterID, default: []].append(id)
                }

                // Build ProjectCluster objects
                let colors = ["#7C3AED", "#2563EB", "#059669", "#D97706", "#DC2626", "#EC4899", "#8B5CF6", "#0891B2"]
                var newClusters: [ProjectCluster] = []

                for (idx, (_, memberIDs)) in clusterGroups.enumerated() {
                    let memberEntries = entries.filter { memberIDs.contains($0.id) }
                    let centroid = self.clusterEngine.computeCentroid(embeddings: memberEntries.map(\.embedding))
                    let name = self.generateClusterName(from: memberEntries)
                    let color = colors[idx % colors.count]

                    let cluster = ProjectCluster(
                        displayName: name,
                        color: color,
                        entryCount: memberIDs.count,
                        centroid: centroid
                    )
                    newClusters.append(cluster)

                    // Assign cluster ID to entries
                    for memberID in memberIDs {
                        try? store.updateCluster(entryID: memberID, clusterID: cluster.id)
                    }
                }

                // Clear cluster assignments for noise entries
                for (id, clusterID) in assignments where clusterID < 0 {
                    try? store.updateCluster(entryID: id, clusterID: nil)
                }

                // Save clusters to DB
                try store.replaceClusters(newClusters)

                await MainActor.run {
                    self.clusters = newClusters
                }
            } catch {
                Logger.shared.error("ContextEngineService: Reclustering failed", error: error)
            }
        }
    }

    /// Look up the cluster for a given prompt's context entry.
    func clusterForEntry(promptID: UUID) -> ProjectCluster? {
        guard let store else { return nil }
        do {
            guard let entry = try store.entryByPromptID(promptID) else { return nil }
            guard let clusterID = entry.clusterID else { return nil }
            return clusters.first { $0.id == clusterID }
        } catch {
            return nil
        }
    }

    /// Delete all context data.
    func clearAllData() {
        guard let store else { return }
        do {
            try store.deleteAll()
            DispatchQueue.main.async {
                self.entryCount = 0
                self.clusters = []
            }
        } catch {
            Logger.shared.error("ContextEngineService: Failed to clear data", error: error)
        }
    }

    // MARK: - Calibration Analytics

    /// Record calibration analytics for an optimization.
    func recordCalibrationAnalytics(
        promptID: UUID,
        detectedTier: ComplexityTier,
        maxOutputWords: Int,
        actualOutputWords: Int,
        compressionTriggered: Bool,
        formattingStripped: Bool,
        verbositySetting: OutputVerbosity
    ) {
        guard let store else { return }

        Task.detached(priority: .utility) { [weak self] in
            do {
                try store.insertCalibrationAnalytics(
                    promptID: promptID,
                    detectedTier: detectedTier.rawValue,
                    maxOutputWords: maxOutputWords,
                    actualOutputWords: actualOutputWords,
                    compressionTriggered: compressionTriggered,
                    formattingStripped: formattingStripped,
                    verbositySetting: verbositySetting.rawValue
                )
                await MainActor.run {
                    self?.refreshEfficiency()
                }
            } catch {
                Logger.shared.error("ContextEngineService: Failed to record calibration analytics", error: error)
            }
        }
    }

    /// Refresh the average output efficiency metric.
    func refreshEfficiency() {
        guard let store else { return }
        do {
            averageOutputEfficiency = try store.averageOutputEfficiency()
        } catch {
            Logger.shared.error("ContextEngineService: Failed to refresh efficiency", error: error)
        }
    }

    // MARK: - Private

    private func refreshCounts() {
        guard let store else { return }
        do {
            entryCount = try store.entryCount()
            clusters = try store.allClusters()
            averageOutputEfficiency = try store.averageOutputEfficiency()
        } catch {
            Logger.shared.error("ContextEngineService: Failed to refresh counts", error: error)
        }
    }

    private func boostScore(similarity: Float, entry: ContextEntry, now: Date) -> Float {
        var score = similarity

        // Recency boost: +0.1 for <24h, linearly decaying over 7 days
        let ageHours = Float(now.timeIntervalSince(entry.lastAccessedAt) / 3600)
        if ageHours < 24 {
            score += 0.1
        } else if ageHours < 168 { // 7 days
            let decay = 0.1 * (1.0 - (ageHours - 24) / 144)
            score += max(0, decay)
        }

        // Frequency boost: +0.01 per access, capped at +0.05
        let frequencyBoost = min(Float(entry.accessCount) * 0.01, 0.05)
        score += frequencyBoost

        return score
    }

    private func selectEntriesWithinBudget(_ matches: [ContextSearchResult], maxTokenBudget: Int) -> [ContextSearchResult] {
        guard !matches.isEmpty else { return [] }

        var selected: [ContextSearchResult] = []
        var usedTokens = 0
        let overhead = 80

        for result in matches {
            let entryTokens = result.entry.tokenCount
            if usedTokens + entryTokens + overhead > maxTokenBudget {
                if selected.isEmpty {
                    selected.append(result)
                }
                break
            }
            selected.append(result)
            usedTokens += entryTokens
        }

        return selected
    }

    private func buildContextXML(entries: [ContextSearchResult], now: Date) -> String {
        var xml = "<user_context relevance=\"high\" entries=\"\(entries.count)\">\n"

        for result in entries {
            let ageString = formatAge(from: result.entry.createdAt, to: now)
            let similarityStr = String(format: "%.2f", result.similarity)
            let sourceType = result.entry.sourceType.rawValue

            // Truncate text to keep within budget
            let maxTextLen = 400
            let text: String
            if result.entry.text.count > maxTextLen {
                text = String(result.entry.text.prefix(maxTextLen)) + "..."
            } else {
                text = result.entry.text
            }

             let filteredText = applyStopPhraseFilter(to: text)
             let project = result.entry.projects.first ?? ""
             let environment = result.entry.environments.first ?? ""
             let technical = result.entry.technicalTerms.prefix(2).joined(separator: ",")

            xml += "  <context_entry source=\"\(sourceType)\" similarity=\"\(similarityStr)\" age=\"\(ageString)\" project=\"\(project.xmlEscaped)\" environment=\"\(environment.xmlEscaped)\" technical=\"\(technical.xmlEscaped)\">\n"
            xml += "    \(filteredText.replacingOccurrences(of: "\n", with: " ").xmlEscaped)\n"
            xml += "  </context_entry>\n"
        }

        xml += "</user_context>"
        return xml
    }

    private func formatAge(from date: Date, to now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }

    /// Stop phrases from PromptCraft system prompts that must never appear in project names.
    private static let stopPhrases: [String] = [
        "you are continuing work",
        "you are a prompt",
        "optimize the following",
        "here is your optimized",
        "the user's input",
        "transformation rules",
        "output calibration",
        "hard constraint",
        "output length limit",
        "critical rule",
        "output only the optimized",
        "prompt optimization engine",
        "maximum impact per word",
        "no preamble",
        "no explanation",
        "raw_prompt",
        "user_context",
        "context_entry",
        "prior context",
        "enforced prefix",
        "enforced suffix",
        "target output structure",
        "absolute prohibitions",
        "tier 1", "tier 2", "tier 3", "tier 4",
        "trivial", "moderate", "complex",
        "anti padding",
        "formatting hint",
        "your sole job",
        "take casual unstructured text",
    ]

    private var dynamicStopPhrases: [String] {
        let builtIns = DefaultStyles.all + [DefaultStyles.shorten]
        return builtIns.compactMap { style in
            let head = String(style.systemInstruction.prefix(50))
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return head.isEmpty ? nil : head
        }
    }

    /// Common English stop words to exclude from project naming.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "shall",
        "should", "may", "might", "must", "can", "could", "to", "of", "in",
        "for", "on", "with", "at", "by", "from", "as", "into", "through",
        "during", "before", "after", "above", "below", "between", "out",
        "and", "but", "or", "nor", "not", "so", "yet", "both", "either",
        "neither", "each", "every", "all", "any", "few", "more", "most",
        "other", "some", "such", "no", "only", "own", "same", "than",
        "too", "very", "just", "also", "now", "here", "there", "when",
        "where", "why", "how", "what", "which", "who", "whom", "this",
        "that", "these", "those", "i", "me", "my", "we", "our", "you",
        "your", "he", "him", "his", "she", "her", "it", "its", "they",
        "them", "their", "make", "use", "get", "add", "set", "put",
    ]

    private func generateClusterName(from entries: [ContextEntry]) -> String {
        // Primary source: structured entities.
        let projects = entries.flatMap(\.projects).map { normalizeEntityToken($0) }.filter { !$0.isEmpty }
        let environments = entries.flatMap(\.environments).map { normalizeEntityToken($0) }.filter { !$0.isEmpty }
        let technicalTerms = entries.flatMap(\.technicalTerms).map { normalizeEntityToken($0) }.filter { !$0.isEmpty }
        let persons = entries.flatMap(\.persons).map { normalizeEntityToken($0) }.filter { !$0.isEmpty }

        if !projects.isEmpty || !environments.isEmpty || !technicalTerms.isEmpty || !persons.isEmpty {
            let topProject = mostFrequentToken(in: projects)
            let topEnvironment = mostFrequentToken(in: environments)
            let topTechnical = mostFrequentToken(in: technicalTerms)
            let topPerson = mostFrequentToken(in: persons)

            var parts: [String] = []
            if let env = topEnvironment { parts.append(env) }
            if let project = topProject {
                parts.append(project)
            } else if let technical = topTechnical {
                parts.append(technical)
            } else if let person = topPerson {
                parts.append(person)
            }

            let entityName = parts.joined(separator: "-")
            if !entityName.isEmpty {
                return String(entityName.prefix(30))
            }
        }

        // Fallback source: text term extraction.
        let allInputText = entries.map(\.text).joined(separator: " ").lowercased()
        let cleaned = applyStopPhraseFilter(to: allInputText)

        let words = cleaned.components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !Self.stopWords.contains($0) }

        var frequency: [String: Int] = [:]
        for word in words {
            frequency[word, default: 0] += 1
        }

        let topTerms = frequency.sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)

        guard !topTerms.isEmpty else { return "Project" }
        return String(topTerms.joined(separator: "-").prefix(30))
    }

    private func mostFrequentToken(in tokens: [String]) -> String? {
        guard !tokens.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for token in tokens where token.count > 1 {
            counts[token, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func normalizeEntityToken(_ token: String) -> String {
        token
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: " ", with: "-")
    }

    private func applyStopPhraseFilter(to text: String) -> String {
        var cleaned = text
        let phrases = Self.stopPhrases + dynamicStopPhrases
        for phrase in phrases where !phrase.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: " ", options: [.caseInsensitive, .diacriticInsensitive], range: nil)
        }
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - EmbeddingEngine

private final class EmbeddingEngine {
    private let embedding: NLEmbedding?

    var isAvailable: Bool { embedding != nil }

    init() {
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// Embed text into a Float vector. Returns nil if embedding is unavailable or fails.
    func embed(_ text: String) -> [Float]? {
        guard let embedding else { return nil }

        // NLEmbedding returns [Double], convert to [Float]
        guard let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }
}

// MARK: - ClusterEngine

private final class ClusterEngine {
    private let epsilon: Float = 0.35
    private let minPoints: Int = 3

    /// Compute cosine similarity between two Float vectors using Accelerate.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0

        a.withUnsafeBufferPointer { aBuf in
            b.withUnsafeBufferPointer { bBuf in
                vDSP_dotpr(aBuf.baseAddress!, 1, bBuf.baseAddress!, 1, &dotProduct, vDSP_Length(a.count))
                vDSP_svesq(aBuf.baseAddress!, 1, &magnitudeA, vDSP_Length(a.count))
                vDSP_svesq(bBuf.baseAddress!, 1, &magnitudeB, vDSP_Length(b.count))
            }
        }

        let denominator = sqrt(magnitudeA) * sqrt(magnitudeB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }

    /// DBSCAN clustering. Returns [UUID: Int] where -1 means noise.
    func dbscan(embeddings: [[Float]], ids: [UUID]) -> [UUID: Int] {
        let n = embeddings.count
        guard n >= minPoints else {
            return Dictionary(uniqueKeysWithValues: ids.map { ($0, -1) })
        }

        // Compute pairwise cosine distances (1 - similarity)
        var distances = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let sim = ClusterEngine.cosineSimilarity(embeddings[i], embeddings[j])
                let dist = 1.0 - sim
                distances[i][j] = dist
                distances[j][i] = dist
            }
        }

        var labels = [Int](repeating: -1, count: n)
        var visited = [Bool](repeating: false, count: n)
        var currentCluster = 0

        for i in 0..<n {
            guard !visited[i] else { continue }
            visited[i] = true

            var neighbors = regionQuery(i, distances: distances)
            if neighbors.count < minPoints {
                labels[i] = -1 // Noise
            } else {
                labels[i] = currentCluster
                expandCluster(i, neighbors: &neighbors, cluster: currentCluster,
                              labels: &labels, visited: &visited, distances: distances)
                currentCluster += 1
            }
        }

        var result: [UUID: Int] = [:]
        for (idx, id) in ids.enumerated() {
            result[id] = labels[idx]
        }
        return result
    }

    /// Compute centroid of a set of embedding vectors.
    func computeCentroid(embeddings: [[Float]]) -> [Float]? {
        guard let first = embeddings.first else { return nil }
        let dim = first.count
        var sum = [Float](repeating: 0, count: dim)

        for embedding in embeddings {
            guard embedding.count == dim else { continue }
            embedding.withUnsafeBufferPointer { eBuf in
                sum.withUnsafeMutableBufferPointer { sBuf in
                    vDSP_vadd(sBuf.baseAddress!, 1, eBuf.baseAddress!, 1, sBuf.baseAddress!, 1, vDSP_Length(dim))
                }
            }
        }

        var count = Float(embeddings.count)
        sum.withUnsafeMutableBufferPointer { buf in
            vDSP_vsdiv(buf.baseAddress!, 1, &count, buf.baseAddress!, 1, vDSP_Length(dim))
        }

        return sum
    }

    // MARK: - DBSCAN Helpers

    private func regionQuery(_ pointIdx: Int, distances: [[Float]]) -> [Int] {
        var neighbors: [Int] = []
        for j in 0..<distances[pointIdx].count {
            if distances[pointIdx][j] <= epsilon {
                neighbors.append(j)
            }
        }
        return neighbors
    }

    private func expandCluster(
        _ pointIdx: Int,
        neighbors: inout [Int],
        cluster: Int,
        labels: inout [Int],
        visited: inout [Bool],
        distances: [[Float]]
    ) {
        var i = 0
        while i < neighbors.count {
            let neighborIdx = neighbors[i]
            if !visited[neighborIdx] {
                visited[neighborIdx] = true
                let neighborNeighbors = regionQuery(neighborIdx, distances: distances)
                if neighborNeighbors.count >= minPoints {
                    for nn in neighborNeighbors where !neighbors.contains(nn) {
                        neighbors.append(nn)
                    }
                }
            }
            if labels[neighborIdx] == -1 {
                labels[neighborIdx] = cluster
            }
            i += 1
        }
    }
}

// MARK: - SQLiteStore

private final class SQLiteStore {
    private var db: OpaquePointer?
    /// Set to true when an old schema DB was migrated (renamed to .bak).
    private(set) var didMigrateFromOldSchema: Bool = false

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("PromptCraft")

        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        let dbURL = appDir.appendingPathComponent("context.db")
        let dbPath = dbURL.path

        // Migration check: if old DB exists without output_text column, rename it
        if FileManager.default.fileExists(atPath: dbPath) {
            var checkDB: OpaquePointer?
            if sqlite3_open(dbPath, &checkDB) == SQLITE_OK {
                let needsMigration = !Self.columnExists("output_text", inTable: "context_entries", db: checkDB)
                sqlite3_close(checkDB)

                if needsMigration {
                    let backupURL = appDir.appendingPathComponent("context.db.bak")
                    try? FileManager.default.removeItem(at: backupURL)
                    try? FileManager.default.moveItem(at: dbURL, to: backupURL)
                    didMigrateFromOldSchema = true
                }
            } else {
                sqlite3_close(checkDB)
            }
        }

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            throw ContextStoreError.openFailed(errorMsg)
        }

        try createTables()
    }

    /// Check if a column exists in a table using PRAGMA table_info.
    private static func columnExists(_ column: String, inTable table: String, db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let nameCStr = sqlite3_column_text(stmt, 1) {
                let name = String(cString: nameCStr)
                if name == column { return true }
            }
        }
        return false
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Schema

    private func createTables() throws {
        let entriesSQL = """
        CREATE TABLE IF NOT EXISTS context_entries (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            output_text TEXT NOT NULL DEFAULT '',
            embedding BLOB NOT NULL,
            persons TEXT NOT NULL DEFAULT '[]',
            projects TEXT NOT NULL DEFAULT '[]',
            environments TEXT NOT NULL DEFAULT '[]',
            technical_terms TEXT NOT NULL DEFAULT '[]',
            source_type TEXT NOT NULL,
            source_prompt_id TEXT,
            cluster_id TEXT,
            created_at REAL NOT NULL,
            last_accessed_at REAL NOT NULL,
            access_count INTEGER DEFAULT 0,
            token_count INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_entries_cluster ON context_entries(cluster_id);
        CREATE INDEX IF NOT EXISTS idx_entries_created ON context_entries(created_at);
        """

        let clustersSQL = """
        CREATE TABLE IF NOT EXISTS project_clusters (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            color TEXT NOT NULL,
            created_at REAL NOT NULL,
            entry_count INTEGER DEFAULT 0,
            centroid BLOB
        );
        """

        guard sqlite3_exec(db, entriesSQL, nil, nil, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to create context_entries table")
        }
        guard sqlite3_exec(db, clustersSQL, nil, nil, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to create project_clusters table")
        }

        let analyticsSQL = """
        CREATE TABLE IF NOT EXISTS calibration_analytics (
            id TEXT PRIMARY KEY,
            prompt_id TEXT NOT NULL,
            detected_tier TEXT NOT NULL,
            max_output_words INTEGER NOT NULL,
            actual_output_words INTEGER NOT NULL,
            compression_triggered INTEGER DEFAULT 0,
            formatting_stripped INTEGER DEFAULT 0,
            verbosity_setting TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """

        guard sqlite3_exec(db, analyticsSQL, nil, nil, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to create calibration_analytics table")
        }

        try migrateEntityColumnsIfNeeded()
    }

    private func migrateEntityColumnsIfNeeded() throws {
        let requiredColumns: [(name: String, definition: String)] = [
            ("persons", "TEXT NOT NULL DEFAULT '[]'"),
            ("projects", "TEXT NOT NULL DEFAULT '[]'"),
            ("environments", "TEXT NOT NULL DEFAULT '[]'"),
            ("technical_terms", "TEXT NOT NULL DEFAULT '[]'")
        ]

        var migratedColumns: [String] = []
        for column in requiredColumns {
            guard !Self.columnExists(column.name, inTable: "context_entries", db: db) else { continue }
            let sql = "ALTER TABLE context_entries ADD COLUMN \(column.name) \(column.definition)"
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw ContextStoreError.queryFailed("Failed to add \(column.name) column")
            }
            migratedColumns.append(column.name)
        }

        if !migratedColumns.isEmpty {
            Logger.shared.info("ContextEngineService: Migrated context_entries with entity columns: \(migratedColumns.joined(separator: ", "))")
        }
    }

    // MARK: - Entry Operations

    func insertEntry(_ entry: ContextEntry) throws {
        let sql = """
        INSERT OR REPLACE INTO context_entries
        (id, text, output_text, embedding, persons, projects, environments, technical_terms, source_type, source_prompt_id, cluster_id, created_at, last_accessed_at, access_count, token_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare insert")
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = entry.id.uuidString
        let embeddingData = embeddingToData(entry.embedding)

        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (entry.text as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (entry.outputText as NSString).utf8String, -1, nil)
        embeddingData.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(embeddingData.count), nil)
        }
        sqlite3_bind_text(stmt, 5, (jsonArray(entry.persons) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (jsonArray(entry.projects) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (jsonArray(entry.environments) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 8, (jsonArray(entry.technicalTerms) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (entry.sourceType.rawValue as NSString).utf8String, -1, nil)

        if let promptID = entry.sourcePromptID {
            sqlite3_bind_text(stmt, 10, (promptID.uuidString as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        if let clusterID = entry.clusterID {
            sqlite3_bind_text(stmt, 11, (clusterID.uuidString as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 11)
        }

        sqlite3_bind_double(stmt, 12, entry.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 13, entry.lastAccessedAt.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 14, Int32(entry.accessCount))
        sqlite3_bind_int(stmt, 15, Int32(entry.tokenCount))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw ContextStoreError.queryFailed("Failed to insert entry")
        }
    }

    func allEntries() throws -> [ContextEntry] {
        let sql = "SELECT id, text, output_text, embedding, persons, projects, environments, technical_terms, source_type, source_prompt_id, cluster_id, created_at, last_accessed_at, access_count, token_count FROM context_entries ORDER BY created_at DESC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare select")
        }
        defer { sqlite3_finalize(stmt) }

        var entries: [ContextEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let entry = readEntry(from: stmt) {
                entries.append(entry)
            }
        }
        return entries
    }

    func entryByPromptID(_ promptID: UUID) throws -> ContextEntry? {
        let sql = "SELECT id, text, output_text, embedding, persons, projects, environments, technical_terms, source_type, source_prompt_id, cluster_id, created_at, last_accessed_at, access_count, token_count FROM context_entries WHERE source_prompt_id = ? LIMIT 1"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare select by prompt ID")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (promptID.uuidString as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return readEntry(from: stmt)
        }
        return nil
    }

    func updateAccess(entryID: UUID) throws {
        let sql = "UPDATE context_entries SET last_accessed_at = ?, access_count = access_count + 1 WHERE id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare access update")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, (entryID.uuidString as NSString).utf8String, -1, nil)

        sqlite3_step(stmt)
    }

    func updateCluster(entryID: UUID, clusterID: UUID?) throws {
        let sql = "UPDATE context_entries SET cluster_id = ? WHERE id = ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare cluster update")
        }
        defer { sqlite3_finalize(stmt) }

        if let clusterID {
            sqlite3_bind_text(stmt, 1, (clusterID.uuidString as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(stmt, 2, (entryID.uuidString as NSString).utf8String, -1, nil)

        sqlite3_step(stmt)
    }

    func entryCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM context_entries"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to count entries")
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    func trimEntries(to maxCount: Int) throws {
        let count = try entryCount()
        guard count > maxCount else { return }

        let deleteCount = count - maxCount
        let sql = "DELETE FROM context_entries WHERE id IN (SELECT id FROM context_entries ORDER BY last_accessed_at ASC LIMIT ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare trim")
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(deleteCount))
        sqlite3_step(stmt)
    }

    func deleteAll() throws {
        guard sqlite3_exec(db, "DELETE FROM context_entries", nil, nil, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to delete entries")
        }
        guard sqlite3_exec(db, "DELETE FROM project_clusters", nil, nil, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to delete clusters")
        }
    }

    // MARK: - Cluster Operations

    func allClusters() throws -> [ProjectCluster] {
        let sql = "SELECT id, display_name, color, created_at, entry_count, centroid FROM project_clusters ORDER BY entry_count DESC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare cluster select")
        }
        defer { sqlite3_finalize(stmt) }

        var clusters: [ProjectCluster] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cluster = readCluster(from: stmt) {
                clusters.append(cluster)
            }
        }
        return clusters
    }

    func replaceClusters(_ clusters: [ProjectCluster]) throws {
        guard sqlite3_exec(db, "DELETE FROM project_clusters", nil, nil, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to clear clusters")
        }

        let sql = """
        INSERT INTO project_clusters (id, display_name, color, created_at, entry_count, centroid)
        VALUES (?, ?, ?, ?, ?, ?)
        """

        for cluster in clusters {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (cluster.id.uuidString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (cluster.displayName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (cluster.color as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 4, cluster.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 5, Int32(cluster.entryCount))

            if let centroid = cluster.centroid {
                let data = embeddingToData(centroid)
                data.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, 6, ptr.baseAddress, Int32(data.count), nil)
                }
            } else {
                sqlite3_bind_null(stmt, 6)
            }

            sqlite3_step(stmt)
        }
    }

    // MARK: - Calibration Analytics

    func insertCalibrationAnalytics(
        promptID: UUID,
        detectedTier: String,
        maxOutputWords: Int,
        actualOutputWords: Int,
        compressionTriggered: Bool,
        formattingStripped: Bool,
        verbositySetting: String
    ) throws {
        let sql = """
        INSERT INTO calibration_analytics
        (id, prompt_id, detected_tier, max_output_words, actual_output_words, compression_triggered, formatting_stripped, verbosity_setting, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare calibration analytics insert")
        }
        defer { sqlite3_finalize(stmt) }

        let id = UUID().uuidString
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (promptID.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (detectedTier as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, Int32(maxOutputWords))
        sqlite3_bind_int(stmt, 5, Int32(actualOutputWords))
        sqlite3_bind_int(stmt, 6, compressionTriggered ? 1 : 0)
        sqlite3_bind_int(stmt, 7, formattingStripped ? 1 : 0)
        sqlite3_bind_text(stmt, 8, (verbositySetting as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 9, Date().timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw ContextStoreError.queryFailed("Failed to insert calibration analytics")
        }
    }

    func averageOutputEfficiency() throws -> Double? {
        let sql = "SELECT AVG(CAST(actual_output_words AS REAL) / CAST(max_output_words AS REAL)) FROM calibration_analytics WHERE max_output_words > 0"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ContextStoreError.queryFailed("Failed to prepare efficiency query")
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let value = sqlite3_column_double(stmt, 0)
            // sqlite3_column_double returns 0.0 for NULL, check column type
            if sqlite3_column_type(stmt, 0) == SQLITE_NULL {
                return nil
            }
            return value
        }
        return nil
    }

    // MARK: - Helpers

    private func readEntry(from stmt: OpaquePointer?) -> ContextEntry? {
        guard let stmt else { return nil }

        // Column order: id(0), text(1), output_text(2), embedding(3), persons(4), projects(5),
        //               environments(6), technical_terms(7), source_type(8), source_prompt_id(9),
        //               cluster_id(10), created_at(11), last_accessed_at(12), access_count(13), token_count(14)

        guard let idCStr = sqlite3_column_text(stmt, 0),
              let textCStr = sqlite3_column_text(stmt, 1),
              let sourceTypeCStr = sqlite3_column_text(stmt, 8),
              let id = UUID(uuidString: String(cString: idCStr)),
              let sourceType = ContextEntry.SourceType(rawValue: String(cString: sourceTypeCStr))
        else { return nil }

        let text = String(cString: textCStr)

        let outputText: String
        if let outputCStr = sqlite3_column_text(stmt, 2) {
            outputText = String(cString: outputCStr)
        } else {
            outputText = ""
        }

        // Read embedding blob
        guard let blobPtr = sqlite3_column_blob(stmt, 3) else { return nil }
        let blobSize = Int(sqlite3_column_bytes(stmt, 3))
        let embedding = dataToEmbedding(Data(bytes: blobPtr, count: blobSize))

        let persons = readJSONArray(stmt: stmt, column: 4)
        let projects = readJSONArray(stmt: stmt, column: 5)
        let environments = readJSONArray(stmt: stmt, column: 6)
        let technicalTerms = readJSONArray(stmt: stmt, column: 7)

        let sourcePromptID: UUID?
        if let cStr = sqlite3_column_text(stmt, 9) {
            sourcePromptID = UUID(uuidString: String(cString: cStr))
        } else {
            sourcePromptID = nil
        }

        let clusterID: UUID?
        if let cStr = sqlite3_column_text(stmt, 10) {
            clusterID = UUID(uuidString: String(cString: cStr))
        } else {
            clusterID = nil
        }

        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11))
        let lastAccessedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
        let accessCount = Int(sqlite3_column_int(stmt, 13))
        let tokenCount = Int(sqlite3_column_int(stmt, 14))

        return ContextEntry(
            id: id,
            text: text,
            outputText: outputText,
            embedding: embedding,
            persons: persons,
            projects: projects,
            environments: environments,
            technicalTerms: technicalTerms,
            sourceType: sourceType,
            sourcePromptID: sourcePromptID,
            clusterID: clusterID,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt,
            accessCount: accessCount,
            tokenCount: tokenCount
        )
    }

    private func readCluster(from stmt: OpaquePointer?) -> ProjectCluster? {
        guard let stmt else { return nil }

        guard let idCStr = sqlite3_column_text(stmt, 0),
              let nameCStr = sqlite3_column_text(stmt, 1),
              let colorCStr = sqlite3_column_text(stmt, 2),
              let id = UUID(uuidString: String(cString: idCStr))
        else { return nil }

        let displayName = String(cString: nameCStr)
        let color = String(cString: colorCStr)
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        let entryCount = Int(sqlite3_column_int(stmt, 4))

        var centroid: [Float]?
        if let blobPtr = sqlite3_column_blob(stmt, 5) {
            let blobSize = Int(sqlite3_column_bytes(stmt, 5))
            if blobSize > 0 {
                centroid = dataToEmbedding(Data(bytes: blobPtr, count: blobSize))
            }
        }

        return ProjectCluster(
            id: id,
            displayName: displayName,
            color: color,
            createdAt: createdAt,
            entryCount: entryCount,
            centroid: centroid
        )
    }

    private func embeddingToData(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buf in
            Data(buffer: buf)
        }
    }

    private func jsonArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func readJSONArray(stmt: OpaquePointer?, column: Int32) -> [String] {
        guard let cStr = sqlite3_column_text(stmt, column) else { return [] }
        let raw = String(cString: cStr)
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func dataToEmbedding(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Float.self)
            return Array(buffer)
        }
    }
}

// MARK: - Errors

private enum ContextStoreError: LocalizedError {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .queryFailed(let msg): return "SQLite query failed: \(msg)"
        }
    }
}

private extension String {
    var xmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
