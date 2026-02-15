import SwiftUI

struct HistoryDetailView: View {
    let entry: PromptHistoryEntry
    @ObservedObject var viewModel: HistoryViewModel
    var onBack: () -> Void
    var onReoptimize: (_ inputText: String, _ styleID: UUID) -> Void
    var onReoptimizeDifferentStyle: (_ inputText: String) -> Void

    @State private var showCopyOutputConfirmation = false
    @State private var showCopyInputConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataSection
                    originalInputSection
                    optimizedOutputSection
                    actionsSection
                }
                .padding(16)
            }
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onBack()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Details")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to history")
            Spacer()

            // Favorite toggle in header
            Button(action: { viewModel.toggleFavorite(entry.id) }) {
                Image(systemName: currentEntry.isFavorited ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(currentEntry.isFavorited ? .yellow : .secondary)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: currentEntry.isFavorited)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(currentEntry.isFavorited ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    /// Live entry from the service so favorite toggles are reflected immediately.
    private var currentEntry: PromptHistoryEntry {
        HistoryService.shared.entries.first { $0.id == entry.id } ?? entry
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Style badge
            HStack(spacing: 4) {
                Image(systemName: viewModel.styleIcon(for: entry.styleID))
                    .font(.system(size: 10))
                Text(viewModel.styleName(for: entry.styleID))
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())

            HStack(spacing: 16) {
                metadataItem(icon: "cpu", text: "\(entry.providerName) / \(entry.modelName)")
                Spacer()
            }

            HStack(spacing: 16) {
                metadataItem(icon: "clock", text: formatTimestamp(entry.timestamp))
                metadataItem(icon: "timer", text: formatDuration(entry.durationMilliseconds))
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metadataItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }

    // MARK: - Original Input

    private var originalInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Original Input")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                copyButton(
                    text: entry.inputText,
                    showConfirmation: $showCopyInputConfirmation,
                    label: "Copy Input"
                )
            }

            ScrollView {
                Text(entry.inputText)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .innerShadowWell(cornerRadius: 8)
        }
    }

    // MARK: - Optimized Output

    private var optimizedOutputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Optimized Prompt")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                copyButton(
                    text: entry.outputText,
                    showConfirmation: $showCopyOutputConfirmation,
                    label: "Copy Output"
                )
            }

            ScrollView {
                Text(entry.outputText)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .innerShadowWell(cornerRadius: 8)
        }
    }

    private func copyButton(
        text: String,
        showConfirmation: Binding<Bool>,
        label: String
    ) -> some View {
        Button(action: {
            ClipboardService.shared.writeText(text)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                showConfirmation.wrappedValue = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showConfirmation.wrappedValue = false
                }
            }
        }) {
            HStack(spacing: 3) {
                Image(systemName: showConfirmation.wrappedValue ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .scaleEffect(showConfirmation.wrappedValue ? 1.1 : 1.0)
                Text(showConfirmation.wrappedValue ? "Copied!" : label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(showConfirmation.wrappedValue ? .green : .accentColor)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: showConfirmation.wrappedValue)
        .accessibilityLabel(showConfirmation.wrappedValue ? "Copied" : label)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 8) {
            // Re-optimize (primary)
            Button(action: { onReoptimize(entry.inputText, entry.styleID) }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                    Text("Re-optimize")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Re-optimize with same style")

            // Re-optimize with a different style
            Button(action: { onReoptimizeDifferentStyle(entry.inputText) }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Text("Re-optimize with Different Style")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(TactileButtonStyle())
            .accessibilityLabel("Re-optimize with a different style")

            // Delete
            Button(action: { showDeleteConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("Delete")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete this optimization record")
            .alert("Delete Entry?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    viewModel.deleteEntry(entry.id)
                    onBack()
                }
            } message: {
                Text("This will permanently delete this optimization record.")
            }
        }
    }
}
