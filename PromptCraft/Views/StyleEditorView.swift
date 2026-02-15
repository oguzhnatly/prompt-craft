import SwiftUI

struct StyleEditorView: View {
    @ObservedObject var viewModel: StyleEditorViewModel

    let onBack: () -> Void
    let onSaved: () -> Void
    let onDuplicateBuiltIn: (PromptStyle) -> Void

    private var isReadOnly: Bool { viewModel.mode.isReadOnly }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    basicsSection
                    sectionDivider
                    systemInstructionSection
                    sectionDivider
                    outputStructureSection
                    sectionDivider
                    toneSection
                    sectionDivider
                    fewShotExamplesSection
                    sectionDivider
                    advancedSection
                    if !isReadOnly {
                        sectionDivider
                        previewSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $viewModel.showAIDescriptionPrompt) {
            aiDescriptionSheet
        }
        .alert("Unsaved Changes", isPresented: $viewModel.showDiscardAlert) {
            Button("Discard", role: .destructive) { onBack() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Discard them?")
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 6) {
            Button(action: handleBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(viewModel.navigationTitle)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isReadOnly {
                Button("Duplicate to Edit") {
                    if case .readOnly(let id) = viewModel.mode,
                       let copy = StyleService.shared.duplicate(id) {
                        onDuplicateBuiltIn(copy)
                    }
                }
                .font(.system(size: 12))
                .controlSize(.small)
            } else {
                if viewModel.mode.isEditing {
                    Button(action: { viewModel.exportStyle() }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Export style")
                }

                Button(action: {
                    if viewModel.save() != nil {
                        onSaved()
                    }
                }) {
                    Text(viewModel.saveButtonTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.isValid ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(viewModel.isValid ? Color.accentColor : Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isValid)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func handleBack() {
        if viewModel.isDirty && !isReadOnly {
            viewModel.showDiscardAlert = true
        } else {
            onBack()
        }
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider().padding(.vertical, 12)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
            .padding(.bottom, 8)
    }

    // MARK: - A) Basics Section

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Basics")

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Style name (max 40 chars)", text: $viewModel.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(isReadOnly)
                if let error = viewModel.nameError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            // Short Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Short Description")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Brief description (max 100 chars)", text: $viewModel.shortDescription)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(isReadOnly)
            }

            // Category
            HStack {
                Text("Category")
                    .font(.system(size: 13))
                Spacer()
                Picker("", selection: $viewModel.category) {
                    ForEach(StyleCategory.allCases, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .frame(width: 160)
                .disabled(isReadOnly)
                .onChange(of: viewModel.category) { newCat in
                    if case .create = viewModel.mode {
                        viewModel.applyCategoryDefaults()
                    }
                }
            }

            // Icon Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                iconPicker
            }
        }
        .padding(.top, 12)
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 10), spacing: 6) {
                ForEach(StyleEditorViewModel.availableIcons, id: \.self) { icon in
                    Button(action: {
                        if !isReadOnly { viewModel.iconName = icon }
                    }) {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .frame(width: 28, height: 28)
                            .background(
                                viewModel.iconName == icon
                                    ? Color.accentColor.opacity(0.2)
                                    : Color(nsColor: .controlBackgroundColor)
                            )
                            .foregroundColor(
                                viewModel.iconName == icon ? Color.accentColor : Color.primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        viewModel.iconName == icon
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: viewModel.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("SF Symbol name", text: $viewModel.iconName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 180)
                    .disabled(isReadOnly)
            }
        }
    }

    // MARK: - B) System Instruction Section

    private var systemInstructionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("System Instruction")
                Spacer()
                if !isReadOnly {
                    Button(action: { viewModel.showAIDescriptionPrompt = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11))
                            Text("Generate with AI")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isGeneratingInstruction)
                }
            }

            ZStack(alignment: .topLeading) {
                if viewModel.systemInstruction.isEmpty && !isReadOnly {
                    Text("Describe how the AI should transform casual text into an optimized prompt for this style. Include: what sections the output should have, what tone to use, what to emphasize, and what to avoid.")
                        .foregroundStyle(.secondary.opacity(0.6))
                        .font(.system(size: 12))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.systemInstruction)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .disabled(isReadOnly)
                    .opacity(isReadOnly ? 0.8 : 1.0)
            }
            .frame(minHeight: 160)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            if let error = viewModel.instructionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Text("\(viewModel.systemInstruction.count) chars")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("~\(viewModel.systemInstructionTokenEstimate) tokens")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let warning = viewModel.styleDefinitionLengthWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(warning)
                        .font(.system(size: 10))
                }
                .foregroundStyle(.orange)
            }

            if viewModel.isGeneratingInstruction {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Generating...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { viewModel.cancelGeneration() }
                        .font(.system(size: 11))
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - AI Description Sheet

    private var aiDescriptionSheet: some View {
        VStack(spacing: 16) {
            Text("Describe Your Style")
                .font(.system(size: 15, weight: .semibold))

            Text("Describe your style in plain language. The AI will generate a system instruction for you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $viewModel.aiDescriptionInput)
                .font(.system(size: 13))
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            Text("Example: \"I want a style for writing Jira tickets that extracts acceptance criteria, priority, and assigns story points.\"")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .italic()

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.showAIDescriptionPrompt = false
                }
                .controlSize(.regular)

                Button("Generate") {
                    viewModel.generateSystemInstruction()
                }
                .controlSize(.regular)
                .keyboardShortcut(.return)
                .disabled(viewModel.aiDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    // MARK: - C) Output Structure Section

    private var outputStructureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Output Structure")

            Text("Define the sections the optimized prompt should contain.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ForEach(Array(viewModel.outputSections.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    TextField("Section name", text: $viewModel.outputSections[index])
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .disabled(isReadOnly)

                    if !isReadOnly {
                        Button(action: { viewModel.removeOutputSection(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !isReadOnly {
                Button(action: { viewModel.addOutputSection() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add Section")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - D) Tone Section

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tone")

            TextField("e.g., formal and precise", text: $viewModel.toneDescriptor)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .disabled(isReadOnly)

            if !isReadOnly {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(StyleEditorViewModel.tonePresets, id: \.self) { tone in
                            Button(action: {
                                if viewModel.toneDescriptor.isEmpty {
                                    viewModel.toneDescriptor = tone.lowercased()
                                } else {
                                    viewModel.toneDescriptor += ", \(tone.lowercased())"
                                }
                            }) {
                                Text(tone)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - E) Few-Shot Examples Section

    private var fewShotExamplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showExamples.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.showExamples ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Text("FEW-SHOT EXAMPLES")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                    if !viewModel.examples.isEmpty {
                        Text("(\(viewModel.examples.count))")
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if viewModel.showExamples {
                Text("Examples help the AI understand your style. 2-3 diverse examples produce the best results.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.examples.enumerated()), id: \.element.id) { index, example in
                    examplePairView(index: index)
                }

                HStack(spacing: 12) {
                    if !isReadOnly {
                        Button(action: { viewModel.addExample() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                Text("Add Example")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button(action: { viewModel.generateExample() }) {
                            HStack(spacing: 4) {
                                if viewModel.isGeneratingExample {
                                    ProgressView().controlSize(.small).scaleEffect(0.6)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 11))
                                }
                                Text("Generate Example")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isGeneratingExample || viewModel.systemInstruction.isEmpty)
                    }
                }

                if viewModel.isGeneratingExample {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                        Text("Generating example...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { viewModel.cancelGeneration() }
                            .font(.system(size: 11))
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func examplePairView(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Example \(index + 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !isReadOnly {
                    Button(action: { viewModel.removeExample(at: index) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Casual Input")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.examples[index].input)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 50, maxHeight: 80)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .disabled(isReadOnly)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Optimized Output")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.examples[index].output)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 50, maxHeight: 80)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                    .disabled(isReadOnly)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - F) Advanced Section

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.showAdvanced.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Text("ADVANCED")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if viewModel.showAdvanced {
                VStack(alignment: .leading, spacing: 10) {
                    // Enforced Prefix
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enforced Prefix")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("Text prepended to every optimized prompt", text: $viewModel.enforcedPrefix)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .disabled(isReadOnly)
                    }

                    // Enforced Suffix
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enforced Suffix")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("Text appended to every optimized prompt", text: $viewModel.enforcedSuffix)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .disabled(isReadOnly)
                    }

                    // Target Model
                    HStack {
                        Text("Target Model")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $viewModel.targetModelHint) {
                            ForEach(TargetModelHint.allCases, id: \.self) { hint in
                                Text(hint.displayName).tag(hint)
                            }
                        }
                        .frame(width: 140)
                        .disabled(isReadOnly)
                    }
                }
                .padding(.leading, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - G) Preview & Test Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Test This Style")

            HStack(spacing: 6) {
                TextField("Type a sample casual prompt...", text: $viewModel.previewInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { viewModel.runPreview() }

                if viewModel.isPreviewRunning {
                    Button("Stop") { viewModel.cancelPreview() }
                        .font(.system(size: 12))
                        .controlSize(.small)
                } else {
                    Button("Preview") { viewModel.runPreview() }
                        .font(.system(size: 12))
                        .controlSize(.small)
                        .disabled(
                            viewModel.previewInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || viewModel.systemInstruction.isEmpty
                        )
                }
            }

            if !viewModel.previewOutput.isEmpty || viewModel.isPreviewRunning {
                VStack(alignment: .leading, spacing: 4) {
                    if viewModel.isPreviewRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                            Text("Running preview...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ScrollView {
                        Text(viewModel.previewOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                    .frame(maxHeight: 150)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            }
        }
    }
}
