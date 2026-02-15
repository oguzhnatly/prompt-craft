import SwiftUI

struct TemplateEditorView: View {
    @ObservedObject var viewModel: TemplateEditorViewModel

    let onBack: () -> Void
    let onSaved: () -> Void
    let onDuplicateBuiltIn: (PromptTemplate) -> Void

    private var isReadOnly: Bool { viewModel.mode.isReadOnly }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    basicsSection
                    sectionDivider
                    templateTextSection
                    sectionDivider
                    placeholderPreview
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
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
                       let copy = TemplateService.shared.duplicate(id) {
                        onDuplicateBuiltIn(copy)
                    }
                }
                .font(.system(size: 12))
                .controlSize(.small)
            } else {
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

    // MARK: - Basics Section

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Basics")

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Template name (max 60 chars)", text: $viewModel.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(isReadOnly)
                if let error = viewModel.nameError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Brief description", text: $viewModel.description)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .disabled(isReadOnly)
            }

            // Category
            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                categoryPicker
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

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TemplateEditorViewModel.categoryPresets, id: \.self) { preset in
                    Button(action: {
                        if !isReadOnly { viewModel.category = preset }
                    }) {
                        Text(preset)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                viewModel.category == preset
                                    ? Color.accentColor
                                    : Color(nsColor: .controlBackgroundColor)
                            )
                            .foregroundStyle(viewModel.category == preset ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        viewModel.category == preset
                                            ? Color.clear
                                            : Color(nsColor: .separatorColor),
                                        lineWidth: 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Icon Picker

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 10), spacing: 6) {
            ForEach(TemplateEditorViewModel.availableIcons, id: \.self) { icon in
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
                .disabled(isReadOnly)
            }
        }
    }

    // MARK: - Template Text Section

    private var templateTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Template Text")

            Text("Use {{placeholder_name}} for dynamic values that users fill in.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.templateText)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 160)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .disabled(isReadOnly)

            if let error = viewModel.templateTextError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Text("\(viewModel.templateText.count) chars")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Placeholder Preview

    private var placeholderPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Detected Placeholders")

            if viewModel.extractedPlaceholders.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("No placeholders detected. Use {{name}} syntax to add dynamic fields.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.extractedPlaceholders, id: \.self) { placeholder in
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16)
                            Text(placeholder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("\(viewModel.extractedPlaceholders.count) placeholder\(viewModel.extractedPlaceholders.count == 1 ? "" : "s") will become input fields when the template is used.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
