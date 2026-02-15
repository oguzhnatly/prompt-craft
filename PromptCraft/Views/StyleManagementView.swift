import SwiftUI
import UniformTypeIdentifiers

struct StyleManagementView: View {
    @ObservedObject private var styleService = StyleService.shared

    let onBack: () -> Void
    let onNewStyle: () -> Void
    let onEditStyle: (PromptStyle) -> Void

    @State private var deleteTarget: PromptStyle?
    @State private var showDeleteConfirmation = false

    private var sortedStyles: [PromptStyle] {
        styleService.getAll()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            styleList
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Styles")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to settings")
            Spacer()

            importButton

            Button(action: onNewStyle) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Create new style")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: - Import

    private var importButton: some View {
        Button(action: importStyle) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Import style from file")
    }

    private func importStyle() {
        lockPopover(true)
        defer { lockPopover(false) }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            if styleService.importStyle(from: data) != nil {
                // Success — the list updates automatically via @Published
            }
        }
    }

    // MARK: - Style List

    private var styleList: some View {
        List {
            ForEach(sortedStyles) { style in
                styleRow(style)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .onMove(perform: moveStyles)
        }
        .listStyle(.plain)
        .alert("Delete Style?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    styleService.delete(target.id)
                    deleteTarget = nil
                }
            }
        } message: {
            Text("This will permanently delete \"\(deleteTarget?.displayName ?? "")\". This cannot be undone.")
        }
    }

    // MARK: - Style Row

    private func styleRow(_ style: PromptStyle) -> some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: style.iconName)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Name + description
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(style.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(style.isBuiltIn ? "Built-in" : "Custom")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(style.isBuiltIn ? Color.secondary : Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            style.isBuiltIn
                                ? Color.secondary.opacity(0.15)
                                : Color.accentColor.opacity(0.15)
                        )
                        .clipShape(Capsule())
                }

                Text(style.shortDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Enable/disable toggle (Automatic is always on)
            if style.id == DefaultStyles.defaultStyleID {
                Toggle("", isOn: .constant(true))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(true)
            } else {
                Toggle("", isOn: Binding(
                    get: { style.isEnabled },
                    set: { newValue in
                        if newValue {
                            styleService.enable(style.id)
                        } else {
                            styleService.disable(style.id)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            // Action buttons (built-in styles have no view/edit/delete)
            if !style.isBuiltIn {
                Button(action: { onEditStyle(style) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit")

                Button(action: {
                    deleteTarget = style
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if !style.isBuiltIn {
                Button("Edit") { onEditStyle(style) }
                Button("Duplicate") {
                    styleService.duplicate(style.id)
                }
                Divider()
            }
            if style.id != DefaultStyles.defaultStyleID {
                Button(style.isEnabled ? "Disable" : "Enable") {
                    if style.isEnabled {
                        styleService.disable(style.id)
                    } else {
                        styleService.enable(style.id)
                    }
                }
            }
            if !style.isBuiltIn {
                Divider()
                Button("Delete", role: .destructive) {
                    deleteTarget = style
                    showDeleteConfirmation = true
                }
            }
        }
    }

    // MARK: - Reorder

    private func moveStyles(from source: IndexSet, to destination: Int) {
        var ids = sortedStyles.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        styleService.reorder(ids)
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
