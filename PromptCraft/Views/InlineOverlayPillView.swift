import SwiftUI

struct InlineOverlayPillView: View {
    let onOptimize: () -> Void
    let onQuick: () -> Void
    let onDismiss: () -> Void

    @ObservedObject var controller: InlineOverlayController

    private var isAnyProcessing: Bool {
        controller.isQuickProcessing || controller.isOptimizeProcessing
    }

    var body: some View {
        HStack(spacing: 0) {
            // Optimize button (opens popover with text)
            Button(action: onOptimize) {
                HStack(spacing: 4) {
                    if controller.isOptimizeProcessing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Optimize")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(isAnyProcessing)

            // Separator
            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            // Quick optimize button
            Button(action: onQuick) {
                Group {
                    if controller.isQuickProcessing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                    } else if controller.showSuccess {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                    } else {
                        Text("Quick")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .frame(minWidth: 30)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(isAnyProcessing)

            // Separator
            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(isAnyProcessing)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .overlay(
            Capsule()
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
        )
        .fixedSize()
    }
}
