import XCTest
@testable import PromptCraft

final class HistoryServiceTests: TempDirectoryTestCase {

    private var sut: HistoryService!
    private var configService: ConfigurationService!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "com.promptcraft.historytest.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)
        configService = ConfigurationService(defaults: testDefaults, configKey: "testHistoryConfig")
        sut = HistoryService(baseDirectory: tempDirectory, configurationService: configService)
    }

    override func tearDown() {
        sut = nil
        configService = nil
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Save & Retrieve

    func testSaveEntryAndRetrieveIt() {
        let entry = TestData.sampleHistoryEntry(inputText: "test input")

        sut.save(entry)

        let all = sut.getAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.inputText, "test input")
    }

    func testSaveMultipleEntries() {
        for i in 0..<5 {
            sut.save(TestData.sampleHistoryEntry(inputText: "entry \(i)"))
        }

        XCTAssertEqual(sut.getAll().count, 5)
    }

    // MARK: - Get Recent

    func testGetRecentReturnsInReverseChronologicalOrder() {
        // Save entries with increasing timestamps
        for i in 0..<5 {
            let entry = TestData.sampleHistoryEntry(
                inputText: "entry \(i)",
                timestamp: Date(timeIntervalSinceNow: Double(i))
            )
            sut.save(entry)
        }

        let recent = sut.getRecent(3)
        XCTAssertEqual(recent.count, 3)

        // Most recent entries come first (they were inserted at index 0)
        for i in 1..<recent.count {
            XCTAssertGreaterThanOrEqual(
                recent[i - 1].timestamp,
                recent[i].timestamp,
                "Recent entries should be in reverse chronological order"
            )
        }
    }

    func testGetRecentWithLimitLargerThanCount() {
        sut.save(TestData.sampleHistoryEntry())
        sut.save(TestData.sampleHistoryEntry())

        let recent = sut.getRecent(100)
        XCTAssertEqual(recent.count, 2)
    }

    // MARK: - Favorites

    func testGetFavoritesReturnsOnlyFavoritedEntries() {
        sut.save(TestData.sampleHistoryEntry(inputText: "normal"))
        let favEntry = TestData.sampleHistoryEntry(inputText: "favorite", isFavorited: true)
        sut.save(favEntry)
        sut.save(TestData.sampleHistoryEntry(inputText: "also normal"))

        // The entry is saved with isFavorited already set
        // But HistoryService.save doesn't alter isFavorited, so let's toggle it
        let favorites = sut.getFavorites()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.inputText, "favorite")
    }

    func testToggleFavoriteTogglesFlag() {
        let entry = TestData.sampleHistoryEntry(isFavorited: false)
        sut.save(entry)

        XCTAssertFalse(sut.getAll().first!.isFavorited)

        sut.toggleFavorite(entry.id)
        XCTAssertTrue(sut.getAll().first!.isFavorited)

        sut.toggleFavorite(entry.id)
        XCTAssertFalse(sut.getAll().first!.isFavorited)
    }

    // MARK: - Delete

    func testDeleteRemovesEntry() {
        let entry = TestData.sampleHistoryEntry()
        sut.save(entry)
        XCTAssertEqual(sut.getAll().count, 1)

        sut.delete(entry.id)
        XCTAssertEqual(sut.getAll().count, 0)
    }

    func testDeleteNonExistentEntryIsNoOp() {
        sut.save(TestData.sampleHistoryEntry())
        sut.delete(UUID()) // Non-existent
        XCTAssertEqual(sut.getAll().count, 1)
    }

    // MARK: - Clear All

    func testClearAllRemovesAllEntries() {
        for _ in 0..<10 {
            sut.save(TestData.sampleHistoryEntry())
        }
        XCTAssertEqual(sut.getAll().count, 10)

        sut.clearAll()
        XCTAssertEqual(sut.getAll().count, 0)
    }

    // MARK: - Search

    func testSearchFindsMatchesInInputText() {
        sut.save(TestData.sampleHistoryEntry(inputText: "explain quantum computing"))
        sut.save(TestData.sampleHistoryEntry(inputText: "write python code"))
        sut.save(TestData.sampleHistoryEntry(inputText: "quantum physics overview"))

        let results = sut.search("quantum")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchFindsMatchesInOutputText() {
        sut.save(TestData.sampleHistoryEntry(
            inputText: "generic input",
            outputText: "The quantum realm is..."
        ))
        sut.save(TestData.sampleHistoryEntry(
            inputText: "another input",
            outputText: "Regular output"
        ))

        let results = sut.search("quantum")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchIsCaseInsensitive() {
        sut.save(TestData.sampleHistoryEntry(inputText: "Python Script"))

        let results = sut.search("python")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchBroadQueryReturnsMultipleMatches() {
        // Both entries share the word "input" in their output text
        sut.save(TestData.sampleHistoryEntry(inputText: "alpha", outputText: "first output result"))
        sut.save(TestData.sampleHistoryEntry(inputText: "beta", outputText: "second output result"))

        let allEntries = sut.getAll()
        XCTAssertEqual(allEntries.count, 2, "Should have 2 entries saved")

        // A broad search term that matches all entries
        let results = sut.search("output")
        XCTAssertEqual(results.count, 2, "Search for common term should return all matching entries")
    }

    // MARK: - Auto-Trim

    func testAutoTrimRemovesOldestEntriesWhenExceedingLimit() {
        // Set a very low history limit
        configService.update { $0.historyLimit = 5 }

        // Save more entries than the limit
        for i in 0..<10 {
            sut.save(TestData.sampleHistoryEntry(
                inputText: "entry \(i)",
                timestamp: Date(timeIntervalSinceNow: Double(i))
            ))
        }

        XCTAssertLessThanOrEqual(sut.getAll().count, 5)
    }

    func testAutoTrimPreservesFavorites() {
        configService.update { $0.historyLimit = 3 }

        // Save a favorite entry first
        let favEntry = TestData.sampleHistoryEntry(
            inputText: "my favorite",
            timestamp: Date(timeIntervalSinceNow: -1000), // Old timestamp
            isFavorited: true
        )
        sut.save(favEntry)

        // Save enough entries to trigger trim
        for i in 0..<5 {
            sut.save(TestData.sampleHistoryEntry(
                inputText: "normal \(i)",
                timestamp: Date(timeIntervalSinceNow: Double(i))
            ))
        }

        let favorites = sut.getFavorites()
        XCTAssertTrue(favorites.contains(where: { $0.inputText == "my favorite" }),
                       "Favorite entries should be preserved during trim")
    }

    // MARK: - Corruption Recovery

    func testCorruptedJSONFileHandledGracefully() {
        // Write corrupted data to history file
        let historyFile = tempDirectory.appendingPathComponent("history.json")
        try? "this is not valid json {{{{".data(using: .utf8)?.write(to: historyFile)

        // Create a new service that will try to load the corrupted file
        let newService = HistoryService(baseDirectory: tempDirectory, configurationService: configService)

        // Should start with empty entries and flag corruption recovery
        XCTAssertEqual(newService.getAll().count, 0)
        XCTAssertTrue(newService.didRecoverFromCorruption)

        // Backup file should exist
        let backupFile = tempDirectory.appendingPathComponent("history.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupFile.path))
    }

    func testDismissCorruptionNotice() {
        let historyFile = tempDirectory.appendingPathComponent("history.json")
        try? "corrupted".data(using: .utf8)?.write(to: historyFile)

        let newService = HistoryService(baseDirectory: tempDirectory, configurationService: configService)
        XCTAssertTrue(newService.didRecoverFromCorruption)

        newService.dismissCorruptionNotice()
        XCTAssertFalse(newService.didRecoverFromCorruption)
    }

    // MARK: - Persistence Across Instances

    func testEntriesPersistAcrossInstances() {
        let entry = TestData.sampleHistoryEntry(inputText: "persistent entry")
        sut.save(entry)

        let newService = HistoryService(baseDirectory: tempDirectory, configurationService: configService)
        let all = newService.getAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.inputText, "persistent entry")
    }

    // MARK: - Empty State

    func testNewServiceStartsEmpty() {
        XCTAssertEqual(sut.getAll().count, 0)
        XCTAssertFalse(sut.didRecoverFromCorruption)
    }
}
