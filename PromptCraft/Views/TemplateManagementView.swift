import SwiftUI
import UniformTypeIdentifiers

struct TemplateManagementView: View {
    @ObservedObject private var templateService = TemplateService.shared

    let onBack: () -> Void
    let onNewTemplate: () -> Void
    let onEditTemplate: (PromptTemplate) -> Void
    let onViewTemplate: (PromptTemplate) -> Void

    @State private var deleteTarget: PromptTemplate?
    @State private var showDeleteConfirmation = false
    @State private var showRestoreConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            templateList
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Templates")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to settings")
            Spacer()

            importButton

            Button(action: onNewTemplate) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create new template")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Import

    private var importButton: some View {
        Button(action: importTemplate) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Import template from file")
    }

    private func importTemplate() {
        lockPopover(true)
        defer { lockPopover(false) }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            _ = templateService.importFromJSON(data)
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        List {
            ForEach(templateService.templates) { template in
                templateRow(template)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            // Restore built-ins button
            if templateService.hasDeletedBuiltIns {
                Section {
                    Button(action: { showRestoreConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                            Text("Restore Built-in Templates")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
        }
        .listStyle(.plain)
        .alert("Delete Template?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    templateService.delete(target.id)
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                if target.isBuiltIn {
                    Text("This will remove the built-in template \"\(target.name)\". You can restore it later from this screen.")
                } else {
                    Text("This will permanently delete \"\(target.name)\". This cannot be undone.")
                }
            }
        }
        .alert("Restore Built-in Templates?", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                templateService.restoreAllBuiltIns()
            }
        } message: {
            Text("This will restore all deleted built-in templates.")
        }
    }

    // MARK: - Template Row

    private func templateRow(_ template: PromptTemplate) -> some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: template.iconName)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Name + description
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(template.isBuiltIn ? "Built-in" : "Custom")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(template.isBuiltIn ? Color.secondary : Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            template.isBuiltIn
                                ? Color.secondary.opacity(0.15)
                                : Color.accentColor.opacity(0.15)
                        )
                        .clipShape(Capsule())
                }

                Text(template.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action buttons
            if template.isBuiltIn {
                Button(action: { onViewTemplate(template) }) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("View (read-only)")
            } else {
                Button(action: { onEditTemplate(template) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit")
            }

            Button(action: {
                deleteTarget = template
                showDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if template.isBuiltIn {
                Button("View") { onViewTemplate(template) }
                Button("Duplicate to Edit") {
                    if let copy = templateService.duplicate(template.id) {
                        onEditTemplate(copy)
                    }
                }
            } else {
                Button("Edit") { onEditTemplate(template) }
                Button("Duplicate") {
                    _ = templateService.duplicate(template.id)
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                deleteTarget = template
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Helpers

    private func lockPopover(_ locked: Bool) {
        NotificationCenter.default.post(
            name: AppConstants.Notifications.lockPopover,
            object: nil,
            userInfo: ["locked": locked]
        )
    }
}
