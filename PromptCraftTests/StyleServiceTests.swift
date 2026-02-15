import XCTest
@testable import PromptCraft

final class StyleServiceTests: TempDirectoryTestCase {

    private var sut: StyleService!

    override func setUp() {
        super.setUp()
        sut = StyleService(baseDirectory: tempDirectory)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization

    func testBuiltInStylesLoadedOnInit() {
        let styles = sut.getAll()
        let builtIn = styles.filter(\.isBuiltIn)
        XCTAssertEqual(builtIn.count, DefaultStyles.all.count)
    }

    func testAllBuiltInStylesPresent() {
        for defaultStyle in DefaultStyles.all {
            let found = sut.getById(defaultStyle.id)
            XCTAssertNotNil(found, "Built-in style '\(defaultStyle.displayName)' should be loaded")
        }
    }

    // MARK: - Create

    func testCreateCustomStyleAddsToCollection() {
        let initialCount = sut.styles.count
        let newStyle = TestData.sampleStyle(displayName: "My Custom Style")

        sut.create(newStyle)

        XCTAssertEqual(sut.styles.count, initialCount + 1)
        let found = sut.styles.first { $0.displayName == "My Custom Style" }
        XCTAssertNotNil(found)
        XCTAssertFalse(found!.isBuiltIn)
    }

    func testCreateAssignsNewSortOrder() {
        let style1 = TestData.sampleStyle(displayName: "Custom 1", sortOrder: 0)
        let created = sut.create(style1)

        XCTAssertGreaterThan(created.sortOrder, 0, "New style should get a sort order > 0 (after built-ins)")
    }

    // MARK: - Update

    func testUpdateCustomStylePersistsChanges() {
        var created = sut.create(TestData.sampleStyle(displayName: "Original"))
        created.displayName = "Updated Name"

        sut.update(created)

        let found = sut.getById(created.id)
        XCTAssertEqual(found?.displayName, "Updated Name")
    }

    func testUpdateSetsModifiedDate() {
        let created = sut.create(TestData.sampleStyle())
        let originalModifiedAt = created.modifiedAt

        // Small delay to ensure timestamp difference
        Thread.sleep(forTimeInterval: 0.01)

        var updated = created
        updated.displayName = "Changed"
        sut.update(updated)

        let found = sut.getById(created.id)
        XCTAssertNotNil(found)
        XCTAssertGreaterThan(found!.modifiedAt, originalModifiedAt)
    }

    // MARK: - Delete

    func testDeleteCustomStyleRemovesIt() {
        let created = sut.create(TestData.sampleStyle(displayName: "To Delete"))
        XCTAssertNotNil(sut.getById(created.id))

        sut.delete(created.id)

        XCTAssertNil(sut.getById(created.id))
    }

    func testBuiltInStyleCannotBeDeleted() {
        let builtInStyle = DefaultStyles.all.first!

        sut.delete(builtInStyle.id)

        XCTAssertNotNil(sut.getById(builtInStyle.id), "Built-in style should not be deleted")
    }

    // MARK: - Duplicate

    func testDuplicateCreatesProperCopy() {
        let original = DefaultStyles.all.first!

        let copy = sut.duplicate(original.id)

        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copy!.id, original.id)
        XCTAssertTrue(copy!.displayName.contains("(Copy)"))
        XCTAssertFalse(copy!.isBuiltIn)
        XCTAssertEqual(copy!.systemInstruction, original.systemInstruction)
        XCTAssertEqual(copy!.fewShotExamples, original.fewShotExamples)
        XCTAssertEqual(copy!.category, original.category)
    }

    func testDuplicateNonExistentStyleReturnsNil() {
        let result = sut.duplicate(UUID())
        XCTAssertNil(result)
    }

    // MARK: - Reorder

    func testReorderChangesSortOrder() {
        let created1 = sut.create(TestData.sampleStyle(displayName: "A"))
        let created2 = sut.create(TestData.sampleStyle(displayName: "B"))

        // Reorder: B before A
        sut.reorder([created2.id, created1.id])

        let s1 = sut.getById(created1.id)!
        let s2 = sut.getById(created2.id)!
        XCTAssertGreaterThan(s1.sortOrder, s2.sortOrder)
    }

    // MARK: - Enable / Disable

    func testDisableTogglesStyleVisibility() {
        let style = DefaultStyles.all.first!
        XCTAssertTrue(sut.getById(style.id)!.isEnabled)

        sut.disable(style.id)
        XCTAssertFalse(sut.getById(style.id)!.isEnabled)

        sut.enable(style.id)
        XCTAssertTrue(sut.getById(style.id)!.isEnabled)
    }

    func testGetEnabledExcludesDisabledStyles() {
        let style = DefaultStyles.all.first!
        let initialEnabled = sut.getEnabled().count

        sut.disable(style.id)

        XCTAssertEqual(sut.getEnabled().count, initialEnabled - 1)
    }

    // MARK: - Export / Import

    func testExportProducesValidJSONThatCanBeReimported() {
        let created = sut.create(TestData.sampleStyle(
            displayName: "Export Test",
            systemInstruction: "Test instruction for export"
        ))

        let exportData = sut.exportStyle(created.id)
        XCTAssertNotNil(exportData)

        // Import into the same service
        let imported = sut.importStyle(from: exportData!)
        XCTAssertNotNil(imported)
        XCTAssertNotEqual(imported!.id, created.id) // New ID assigned
        XCTAssertEqual(imported!.displayName, "Export Test")
        XCTAssertEqual(imported!.systemInstruction, "Test instruction for export")
        XCTAssertFalse(imported!.isBuiltIn)
    }

    func testImportWithInvalidJSONFailsGracefully() {
        let invalidData = "not valid json at all".data(using: .utf8)!
        let result = sut.importStyle(from: invalidData)
        XCTAssertNil(result)
    }

    func testExportNonExistentStyleReturnsNil() {
        let data = sut.exportStyle(UUID())
        XCTAssertNil(data)
    }

    // MARK: - Persistence Across Instances

    func testCustomStylesPersistAcrossInstances() {
        let created = sut.create(TestData.sampleStyle(displayName: "Persistent Style"))

        // Create a new service instance pointing to the same directory
        let newService = StyleService(baseDirectory: tempDirectory)

        let found = newService.getById(created.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.displayName, "Persistent Style")
    }

    func testDisableStatePersistsAcrossInstances() {
        let style = DefaultStyles.all.first!
        sut.disable(style.id)

        let newService = StyleService(baseDirectory: tempDirectory)
        XCTAssertFalse(newService.getById(style.id)!.isEnabled)
    }

    // MARK: - Sorted Output

    func testGetAllReturnsSortedStyles() {
        let styles = sut.getAll()
        for i in 1..<styles.count {
            XCTAssertLessThanOrEqual(
                styles[i - 1].sortOrder, styles[i].sortOrder,
                "Styles should be sorted by sortOrder"
            )
        }
    }
}
