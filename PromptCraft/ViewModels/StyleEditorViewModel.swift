import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

// MARK: - Editable Few-Shot Example

/// Identifiable wrapper for editing FewShotExample in SwiftUI lists.
struct EditableFewShotExample: Identifiable {
    let id = UUID()
    var input: String
    var output: String

    init(from example: FewShotExample) {
        self.input = example.input
        self.output = example.output
    }

    init(input: String = "", output: String = "") {
        self.input = input
        self.output = output
    }

    var toFewShotExample: FewShotExample {
        FewShotExample(input: input, output: output)
    }
}

// MARK: - StyleEditorViewModel

final class StyleEditorViewModel: ObservableObject {

    // MARK: - Mode

    enum Mode {
        case create
        case edit(UUID)
        case readOnly(UUID)

        var isReadOnly: Bool {
            if case .readOnly = self { return true }
            return false
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    let mode: Mode

    // MARK: - Draft State

    @Published var name: String = ""
    @Published var shortDescription: String = ""
    @Published var category: StyleCategory = .custom
    @Published var iconName: String = "sparkles"
    @Published var systemInstruction: String = ""
    @Published var outputSections: [String] = []
    @Published var toneDescriptor: String = ""
    @Published var examples: [EditableFewShotExample] = []
    @Published var enforcedPrefix: String = ""
    @Published var enforcedSuffix: String = ""
    @Published var targetModelHint: TargetModelHint = .any
    @Published var showAdvanced: Bool = false
    @Published var showExamples: Bool = false

    // MARK: - AI Generation State

    @Published var isGeneratingInstruction: Bool = false
    @Published var aiDescriptionInput: String = ""
    @Published var showAIDescriptionPrompt: Bool = false

    @Published var isGeneratingExample: Bool = false

    // MARK: - Preview State

    @Published var previewInput: String = ""
    @Published var previewOutput: String = ""
    @Published var isPreviewRunning: Bool = false

    // MARK: - Validation

    @Published var nameError: String?
    @Published var instructionError: String?

    // MARK: - Dirty Tracking

    @Published var isDirty: Bool = false
    @Published var showDiscardAlert: Bool = false

    // MARK: - Services

    private let styleService: StyleService
    private let providerManager: LLMProviderManager
    private let configurationService: ConfigurationService
    private let promptAssembler: PromptAssembler
    private var cancellables = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?

    private var originalStyle: PromptStyle?

    // MARK: - Init

    init(
        mode: Mode,
        styleService: StyleService = .shared,
        providerManager: LLMProviderManager = .shared,
        configurationService: ConfigurationService = .shared,
        promptAssembler: PromptAssembler = .shared
    ) {
        self.mode = mode
        self.styleService = styleService
        self.providerManager = providerManager
        self.configurationService = configurationService
        self.promptAssembler = promptAssembler

        switch mode {
        case .create:
            applyDefaults()
        case .edit(let id), .readOnly(let id):
            if let style = styleService.getById(id) {
                loadStyle(style)
                originalStyle = style
            }
        }

        observeChanges()
    }

    deinit {
        currentTask?.cancel()
    }

    // MARK: - Category Defaults

    static func defaultOutputStructure(for category: StyleCategory) -> [String] {
        switch category {
        case .technical:
            return ["Problem Statement", "Requirements", "Constraints", "Acceptance Criteria"]
        case .creative:
            return ["Theme", "Style Guidelines", "Key Elements", "Tone"]
        case .business:
            return ["Objective", "Stakeholders", "Deliverables", "Timeline"]
        case .research:
            return ["Research Question", "Methodology", "Scope", "Expected Outcomes"]
        case .communication:
            return ["Audience", "Key Message", "Call to Action", "Format"]
        case .custom:
            return ["Context", "Task", "Output Format"]
        }
    }

    // MARK: - SF Symbol Icons

    static let availableIcons: [String] = [
        "sparkles", "hammer", "magnifyingglass", "doc.text", "pencil",
        "lightbulb", "chart.bar", "envelope", "exclamationmark.triangle", "person",
        "globe", "ladybug", "arrow.triangle.branch", "paintbrush", "gearshape",
        "book", "flag", "star", "bolt", "flame",
        "leaf", "cpu", "terminal", "list.bullet", "checkmark.circle",
        "wand.and.stars", "text.alignleft", "paperplane", "tray", "lock",
    ]

    // MARK: - Tone Presets

    static let tonePresets: [String] = [
        "Formal", "Conversational", "Technical", "Urgent", "Analytical", "Creative",
    ]

    // MARK: - Load / Apply

    private func applyDefaults() {
        category = .custom
        outputSections = Self.defaultOutputStructure(for: .custom)
    }

    private func loadStyle(_ style: PromptStyle) {
        name = style.displayName
        shortDescription = style.shortDescription
        category = style.category
        iconName = style.iconName
        systemInstruction = style.systemInstruction
        outputSections = style.outputStructure
        toneDescriptor = style.toneDescriptor
        examples = style.fewShotExamples.map { EditableFewShotExample(from: $0) }
        enforcedPrefix = style.enforcedPrefix ?? ""
        enforcedSuffix = style.enforcedSuffix ?? ""
        targetModelHint = style.targetModelHint
        showExamples = !style.fewShotExamples.isEmpty
        showAdvanced = (style.enforcedPrefix.map { !$0.isEmpty } ?? false)
            || (style.enforcedSuffix.map { !$0.isEmpty } ?? false)
            || style.targetModelHint != .any
    }

    private func observeChanges() {
        // Track dirty state by observing any change to draft fields
        Publishers.CombineLatest4(
            $name, $shortDescription, $systemInstruction, $toneDescriptor
        )
        .dropFirst()
        .sink { [weak self] _ in self?.isDirty = true }
        .store(in: &cancellables)

        Publishers.CombineLatest3($category, $iconName, $targetModelHint)
            .dropFirst()
            .sink { [weak self] _ in self?.isDirty = true }
            .store(in: &cancellables)
    }

    // MARK: - Computed

    var systemInstructionTokenEstimate: Int {
        promptAssembler.estimateTokens(systemInstruction)
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Warning message when the total style definition (system instruction + examples) is very long.
    /// Returns nil when the definition length is acceptable.
    var styleDefinitionLengthWarning: String? {
        let examplesLength = examples.reduce(0) { $0 + $1.input.count + $1.output.count }
        let total = systemInstruction.count + examplesLength
        if total > 20_000 {
            return "Your style definition is very long (\(total.formatted()) chars). This uses significant context and may increase costs or reduce output quality."
        } else if total > 10_000 {
            return "Your style definition is long (\(total.formatted()) chars). Consider trimming for best results."
        }
        return nil
    }

    var navigationTitle: String {
        switch mode {
        case .create: return "New Style"
        case .edit: return "Edit Style"
        case .readOnly: return "View Style"
        }
    }

    var saveButtonTitle: String {
        switch mode {
        case .create: return "Create Style"
        case .edit: return "Save"
        case .readOnly: return ""
        }
    }

    // MARK: - Validation

    func validate() -> Bool {
        nameError = nil
        instructionError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            nameError = "Name is required."
            return false
        }
        if trimmedName.count > 40 {
            nameError = "Name must be 40 characters or less."
            return false
        }

        let trimmedInstruction = systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedInstruction.isEmpty {
            instructionError = "System instruction is required."
            return false
        }

        return true
    }

    // MARK: - Save

    func save() -> PromptStyle? {
        guard validate() else { return nil }

        let fewShot = examples.map(\.toFewShotExample)
            .filter { !$0.input.isEmpty || !$0.output.isEmpty }

        switch mode {
        case .create:
            let style = PromptStyle(
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                shortDescription: shortDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                iconName: iconName,
                sortOrder: 0,
                isBuiltIn: false,
                isEnabled: true,
                systemInstruction: systemInstruction,
                outputStructure: outputSections.filter { !$0.isEmpty },
                toneDescriptor: toneDescriptor,
                fewShotExamples: fewShot,
                enforcedPrefix: enforcedPrefix.isEmpty ? nil : enforcedPrefix,
                enforcedSuffix: enforcedSuffix.isEmpty ? nil : enforcedSuffix,
                targetModelHint: targetModelHint
            )
            let created = styleService.create(style)
            isDirty = false
            return created

        case .edit(let id):
            guard var existing = styleService.getById(id) else { return nil }
            existing.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.shortDescription = shortDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.category = category
            existing.iconName = iconName
            existing.systemInstruction = systemInstruction
            existing.outputStructure = outputSections.filter { !$0.isEmpty }
            existing.toneDescriptor = toneDescriptor
            existing.fewShotExamples = fewShot
            existing.enforcedPrefix = enforcedPrefix.isEmpty ? nil : enforcedPrefix
            existing.enforcedSuffix = enforcedSuffix.isEmpty ? nil : enforcedSuffix
            existing.targetModelHint = targetModelHint
            styleService.update(existing)
            isDirty = false
            return existing

        case .readOnly:
            return nil
        }
    }

    // MARK: - Output Sections

    func addOutputSection() {
        outputSections.append("")
        isDirty = true
    }

    func removeOutputSection(at index: Int) {
        guard outputSections.indices.contains(index) else { return }
        outputSections.remove(at: index)
        isDirty = true
    }

    func moveOutputSections(from source: IndexSet, to destination: Int) {
        outputSections.move(fromOffsets: source, toOffset: destination)
        isDirty = true
    }

    func applyCategoryDefaults() {
        outputSections = Self.defaultOutputStructure(for: category)
        isDirty = true
    }

    // MARK: - Examples

    func addExample() {
        examples.append(EditableFewShotExample())
        showExamples = true
        isDirty = true
    }

    func removeExample(at index: Int) {
        guard examples.indices.contains(index) else { return }
        examples.remove(at: index)
        isDirty = true
    }

    // MARK: - Generate System Instruction with AI

    func generateSystemInstruction() {
        guard !aiDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isGeneratingInstruction = true
        let description = aiDescriptionInput

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let metaPrompt = """
            You are a meta-prompt engineer. The user will describe a style of prompt optimization \
            they want in plain language. Your job is to generate a detailed system instruction that \
            will be used inside a prompt optimization tool.

            The system instruction you write will be given to an AI whose job is to take casual, \
            unstructured text and transform it into a well-crafted prompt following this style.

            Your output should:
            1. Define the transformation rules clearly
            2. Specify what structure the optimized prompt should have
            3. Describe the tone and voice to use
            4. Include what to emphasize and what to avoid
            5. Be written as direct instructions to the AI (use "you should", "always", "never")

            Output ONLY the system instruction text. No preamble, no explanation.

            User's style description:
            \(description)
            """

            do {
                let config = self.configurationService.configuration
                let provider = self.providerManager.activeProvider
                let messages = [LLMMessage(role: .user, content: metaPrompt)]
                let parameters = LLMRequestParameters(
                    model: config.selectedModelName,
                    temperature: 0.5,
                    maxTokens: 2048
                )

                var result = ""
                let stream = provider.streamCompletion(messages: messages, parameters: parameters)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    result += chunk
                    self.systemInstruction = result
                }
                self.isDirty = true
            } catch {
                // Silently fail — user can see the partial output
            }

            self.isGeneratingInstruction = false
            self.showAIDescriptionPrompt = false
        }
    }

    // MARK: - Generate Example with AI

    func generateExample() {
        guard !systemInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isGeneratingExample = true

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let prompt = """
            Given the following system instruction for a prompt optimization style, generate one \
            example pair consisting of:
            1. A casual, rough input that a user might type
            2. The optimized prompt that should result from applying this style

            System instruction:
            \(self.systemInstruction)

            Output in exactly this format (no other text):
            INPUT:
            <the casual input>
            OUTPUT:
            <the optimized prompt>
            """

            do {
                let config = self.configurationService.configuration
                let provider = self.providerManager.activeProvider
                let messages = [LLMMessage(role: .user, content: prompt)]
                let parameters = LLMRequestParameters(
                    model: config.selectedModelName,
                    temperature: 0.7,
                    maxTokens: 2048
                )

                var result = ""
                let stream = provider.streamCompletion(messages: messages, parameters: parameters)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    result += chunk
                }

                // Parse the result
                let parsed = parseExampleOutput(result)
                self.examples.append(EditableFewShotExample(input: parsed.input, output: parsed.output))
                self.showExamples = true
                self.isDirty = true
            } catch {
                // Silently fail
            }

            self.isGeneratingExample = false
        }
    }

    private func parseExampleOutput(_ text: String) -> (input: String, output: String) {
        let lines = text.components(separatedBy: "\n")
        var input = ""
        var output = ""
        var section: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("INPUT:") {
                section = "input"
                let remainder = trimmed.dropFirst("INPUT:".count).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty { input += remainder + "\n" }
            } else if trimmed.hasPrefix("OUTPUT:") {
                section = "output"
                let remainder = trimmed.dropFirst("OUTPUT:".count).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty { output += remainder + "\n" }
            } else if let sec = section {
                if sec == "input" {
                    input += line + "\n"
                } else {
                    output += line + "\n"
                }
            }
        }

        return (
            input.trimmingCharacters(in: .whitespacesAndNewlines),
            output.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Preview / Test

    func runPreview() {
        let testInput = previewInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testInput.isEmpty else { return }

        isPreviewRunning = true
        previewOutput = ""

        // Build a temporary style from current draft
        let tempStyle = buildDraftStyle()

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let config = self.configurationService.configuration
                let provider = self.providerManager.activeProvider

                let assembled = self.promptAssembler.assemble(
                    rawInput: testInput,
                    style: tempStyle,
                    providerType: config.selectedProvider
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

                let stream = provider.streamCompletion(messages: messages, parameters: parameters)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    self.previewOutput += chunk
                }
            } catch {
                self.previewOutput = "Error: \(error.localizedDescription)"
            }

            self.isPreviewRunning = false
        }
    }

    func cancelPreview() {
        currentTask?.cancel()
        currentTask = nil
        isPreviewRunning = false
    }

    func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isGeneratingInstruction = false
        isGeneratingExample = false
    }

    private func buildDraftStyle() -> PromptStyle {
        PromptStyle(
            displayName: name,
            shortDescription: shortDescription,
            category: category,
            iconName: iconName,
            sortOrder: 0,
            systemInstruction: systemInstruction,
            outputStructure: outputSections.filter { !$0.isEmpty },
            toneDescriptor: toneDescriptor,
            fewShotExamples: examples.map(\.toFewShotExample).filter { !$0.input.isEmpty || !$0.output.isEmpty },
            enforcedPrefix: enforcedPrefix.isEmpty ? nil : enforcedPrefix,
            enforcedSuffix: enforcedSuffix.isEmpty ? nil : enforcedSuffix,
            targetModelHint: targetModelHint
        )
    }

    // MARK: - Export

    func exportStyle() {
        guard case .edit(let id) = mode, let data = styleService.exportStyle(id) else { return }

        NotificationCenter.default.post(
            name: AppConstants.Notifications.lockPopover,
            object: nil,
            userInfo: ["locked": true]
        )
        defer {
            NotificationCenter.default.post(
                name: AppConstants.Notifications.lockPopover,
                object: nil,
                userInfo: ["locked": false]
            )
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(name.replacingOccurrences(of: " ", with: "-")).promptcraft-style.json"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
