import AppKit
import Combine
import XCTest
@testable import PromptCraft

final class MainViewModelTests: XCTestCase {

    private var sut: MainViewModel!
    private var mockProvider: MockLLMProvider!
    private var styleService: StyleService!
    private var configService: ConfigurationService!
    private var historyService: HistoryService!
    private var providerManager: LLMProviderManager!
    private var tempDirectory: URL!
    private var testDefaults: UserDefaults!
    private var keychainService: KeychainService!
    private var keychainCleanup: (() -> Void)!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()

        // Create temp directory for file-based services
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptCraftVMTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // UserDefaults
        let suiteName = "com.promptcraft.vmtest.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        testDefaults.removePersistentDomain(forName: suiteName)

        // Services
        configService = ConfigurationService(defaults: testDefaults, configKey: "testVMConfig")
        styleService = StyleService(baseDirectory: tempDirectory.appendingPathComponent("styles"))
        historyService = HistoryService(
            baseDirectory: tempDirectory.appendingPathComponent("history"),
            configurationService: configService
        )

        // Keychain
        let keychainResult = KeychainService.testInstance()
        keychainService = keychainResult.service
        keychainCleanup = keychainResult.cleanup

        // Set up a fake API key so optimization doesn't bail early
        keychainService.saveAPIKey(for: .anthropicClaude, key: "test-key")

        // Provider manager
        providerManager = LLMProviderManager(
            configurationService: configService,
            keychainService: keychainService
        )

        // Mock provider
        mockProvider = MockLLMProvider()

        // Create ViewModel
        sut = MainViewModel(
            styleService: styleService,
            configurationService: configService,
            historyService: historyService,
            providerManager: providerManager,
            promptAssembler: .shared,
            clipboardService: .shared,
            networkMonitor: .shared
        )
    }

    override func tearDown() {
        cancellables.removeAll()
        keychainCleanup()
        sut = nil
        mockProvider = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        super.tearDown()
    }

    // MARK: - Character Count

    func testInputTextChangesUpdateCharacterCount() {
        sut.inputText = ""
        XCTAssertEqual(sut.characterCount, 0)

        sut.inputText = "Hello, world!"
        XCTAssertEqual(sut.characterCount, 13)

        sut.inputText = "A longer piece of text for testing character count."
        XCTAssertEqual(sut.characterCount, 51)
    }

    // MARK: - Optimize Button State

    func testEmptyInputDisablesOptimizeButton() {
        sut.inputText = ""
        XCTAssertFalse(sut.isOptimizeEnabled)
    }

    func testWhitespaceOnlyInputDisablesOptimizeButton() {
        sut.inputText = "   \n\t  \n  "
        XCTAssertFalse(sut.isOptimizeEnabled)
    }

    func testNonEmptyInputEnablesOptimizeButton() {
        sut.inputText = "Write a function"
        XCTAssertTrue(sut.isOptimizeEnabled)
    }

    func testProcessingDisablesOptimizeButton() {
        sut.inputText = "Some input"
        sut.isProcessing = true
        XCTAssertFalse(sut.isOptimizeEnabled)
    }

    // MARK: - Style Selection

    func testSelectingStyleUpdatesSelectedStyleProperty() {
        let styles = styleService.getEnabled()
        guard styles.count >= 2 else {
            XCTFail("Need at least 2 styles for this test")
            return
        }

        sut.selectStyle(styles[1])
        XCTAssertEqual(sut.selectedStyle?.id, styles[1].id)
    }

    func testSelectedStyleDescriptionUpdates() {
        let styles = styleService.getEnabled()
        guard let style = styles.first else { return }

        sut.selectStyle(style)
        XCTAssertEqual(sut.selectedStyleDescription, style.shortDescription)
    }

    // MARK: - Cancellation

    func testCancelOptimizationSetsIsProcessingToFalse() {
        sut.isProcessing = true
        sut.cancelOptimization()

        XCTAssertFalse(sut.isProcessing)
        XCTAssertTrue(sut.wasCancelled)
    }

    // MARK: - Clipboard Population

    func testPopulateFromClipboardSetsInputText() {
        sut.populateFromClipboard("Pasted text from clipboard")
        XCTAssertEqual(sut.inputText, "Pasted text from clipboard")
    }

    func testPopulateFromClipboardTruncatesLongText() {
        let longText = String(repeating: "a", count: 15_000)
        sut.populateFromClipboard(longText)

        XCTAssertEqual(sut.inputText.count, AppConstants.Clipboard.maxInputCharacters)
        XCTAssertNotNil(sut.inputTruncationWarning)
    }

    func testPopulateFromClipboardNoTruncationForShortText() {
        sut.populateFromClipboard("Short text")
        XCTAssertNil(sut.inputTruncationWarning)
    }

    // MARK: - Re-optimize

    func testPrepopulateForReoptimizeSetsInputAndStyle() {
        let styles = styleService.getEnabled()
        guard let style = styles.first else { return }

        sut.prepopulateForReoptimize(input: "Re-optimize this", styleID: style.id)

        XCTAssertEqual(sut.inputText, "Re-optimize this")
        XCTAssertEqual(sut.selectedStyle?.id, style.id)
        XCTAssertTrue(sut.outputText.isEmpty)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Long Input Warning

    func testLongInputTriggersWarning() {
        let longInput = String(repeating: "a", count: 60_000)
        sut.inputText = longInput
        sut.selectedStyle = styleService.getEnabled().first

        sut.optimizePrompt()

        XCTAssertTrue(sut.showLongInputWarning)
        XCTAssertEqual(sut.longInputCharCount, 60_000)
    }

    // MARK: - Available Styles

    func testAvailableStylesPopulatedFromStyleService() {
        XCTAssertFalse(sut.availableStyles.isEmpty)
        XCTAssertEqual(sut.availableStyles.count, styleService.getEnabled().count)
    }

    // MARK: - Style Lookup Helpers

    func testStyleDisplayNameLookup() {
        let style = DefaultStyles.all.first!
        let name = sut.styleDisplayName(for: style.id)
        XCTAssertEqual(name, style.displayName)
    }

    func testStyleDisplayNameForUnknownIDReturnsUnknown() {
        let name = sut.styleDisplayName(for: UUID())
        XCTAssertEqual(name, "Unknown")
    }

    func testStyleIconNameLookup() {
        let style = DefaultStyles.all.first!
        let icon = sut.styleIconName(for: style.id)
        XCTAssertEqual(icon, style.iconName)
    }

    // MARK: - Initial State

    func testInitialStateIsCorrect() {
        XCTAssertTrue(sut.inputText.isEmpty)
        XCTAssertTrue(sut.outputText.isEmpty)
        XCTAssertFalse(sut.isProcessing)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.wasCancelled)
        XCTAssertFalse(sut.showLongInputWarning)
        XCTAssertFalse(sut.isPartialResponse)
        XCTAssertNotNil(sut.selectedStyle) // Should default to first available
    }
}
