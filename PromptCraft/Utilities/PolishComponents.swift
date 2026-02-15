import SwiftUI
import AppKit

// MARK: - Blinking Cursor View

/// A thin accent-colored bar that blinks at 500ms intervals during streaming,
/// then blinks twice more and fades out when streaming completes.
struct BlinkingCursorView: View {
    let isStreaming: Bool

    @State private var visible = true
    @State private var hidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 14)
            .opacity(cursorOpacity)
            .onReceive(timer) { _ in
                guard !hidden else { return }
                visible.toggle()
            }
            .onChange(of: isStreaming) { streaming in
                if !streaming {
                    // Blink twice more then fade out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            hidden = true
                        }
                    }
                } else {
                    hidden = false
                    visible = true
                }
            }
    }

    private var cursorOpacity: Double {
        if hidden { return 0 }
        if reduceMotion { return isStreaming ? 0.6 : 0 }
        return visible ? 1 : 0
    }
}

// MARK: - Shimmer Modifier

/// A left-to-right shimmer effect overlay for loading states.
struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = -0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.12), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                    }
                    .clipped()
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        phase = 1.0
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Shake Effect

/// Horizontal shake animation for error states (3 cycles, small amplitude).
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes), y: 0)
        )
    }
}

// MARK: - Pulsing Opacity Modifier

/// Slow opacity pulsing for "alive" empty states.
struct PulsingOpacityModifier: ViewModifier {
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing && !reduceMotion ? 0.4 : 0.75)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Button Pulse Modifier

/// Opacity oscillation for processing buttons (0.8 to 1.0).
struct ButtonPulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing && isActive && !reduceMotion ? 0.8 : 1.0)
            .animation(
                isActive && !reduceMotion
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { if isActive { isPulsing = true } }
            .onChange(of: isActive) { active in isPulsing = active }
    }
}

// MARK: - Bounce Tap Button Style

/// Style pills: scale down to 0.95 then spring back on tap.
struct BounceTapStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.5),
                value: configuration.isPressed
            )
    }
}

// MARK: - Tactile Button Style

/// Optimize button: scale down to 0.97 and darken slightly on press.
struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

// MARK: - Toast Overlay

/// A toast that slides up from the bottom with an icon and message.
struct ToastOverlay: View {
    let message: String
    let icon: String
    let isShowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if isShowing {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
                .padding(.bottom, 8)
            }
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.1)
                : .spring(response: 0.35, dampingFraction: 0.8),
            value: isShowing
        )
    }
}

// MARK: - Three Dots Loading

/// Animated three dots that pulse in sequence during processing.
struct ThreeDotsLoading: View {
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .opacity(dotOpacity(for: index))
            }
        }
        .onReceive(timer) { _ in
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        if reduceMotion { return 0.7 }
        return phase == index ? 1.0 : 0.35
    }
}

// MARK: - Inner Shadow Modifier

/// Creates a subtle inset/well appearance for text areas.
struct InnerShadowModifier: ViewModifier {
    let cornerRadius: CGFloat
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        focused ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                        lineWidth: focused ? 1.5 : 0.5
                    )
                    .animation(.easeInOut(duration: 0.15), value: focused)
            )
            .overlay(
                // Top inset shadow for depth
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.04), .clear],
                            startPoint: .top,
                            endPoint: .init(x: 0.5, y: 0.15)
                        )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: focused ? Color.accentColor.opacity(0.15) : .clear, radius: 3, y: 0)
    }
}

// MARK: - Scroll Gradient Edges

/// Subtle gradient fades at the edges of a horizontal scroll to indicate overflow.
struct ScrollGradientEdges: ViewModifier {
    func body(content: Content) -> some View {
        content
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 12)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 12)
                }
            )
    }
}

// MARK: - View Extensions

extension View {
    func shimmer(isActive: Bool) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }

    func pulsingOpacity() -> some View {
        modifier(PulsingOpacityModifier())
    }

    func buttonPulse(isActive: Bool) -> some View {
        modifier(ButtonPulseModifier(isActive: isActive))
    }

    func innerShadowWell(cornerRadius: CGFloat = 8, focused: Bool = false) -> some View {
        modifier(InnerShadowModifier(cornerRadius: cornerRadius, focused: focused))
    }

    func scrollGradientEdges() -> some View {
        modifier(ScrollGradientEdges())
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 {
                height += spacing
            }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentRowWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Color Hex Extension

extension Color {
    /// Initialize a Color from a hex string (e.g., "#7C3AED" or "7C3AED").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Menubar Icon Generator

enum MenuBarIconGenerator {
    /// Creates a sparkle template image for the menubar (18x18 pt).
    static func createSparkleIcon(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outerRadius = size * 0.42
            let innerRadius = size * 0.13
            let points = 4

            // Main 4-pointed star
            drawStar(in: ctx, center: center, outer: outerRadius, inner: innerRadius, points: points)

            // Small accent sparkle at top-right
            let miniCenter = CGPoint(x: center.x + size * 0.26, y: center.y + size * 0.26)
            drawStar(in: ctx, center: miniCenter, outer: size * 0.12, inner: size * 0.04, points: points)

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Creates the sparkle icon with a small processing dot indicator.
    static func createProcessingIcon(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: rect.midX - 1, y: rect.midY)
            let outerRadius = size * 0.38
            let innerRadius = size * 0.11
            let points = 4

            // Main sparkle (slightly smaller to make room for dot)
            drawStar(in: ctx, center: center, outer: outerRadius, inner: innerRadius, points: points)

            // Mini sparkle
            let miniCenter = CGPoint(x: center.x + size * 0.24, y: center.y + size * 0.24)
            drawStar(in: ctx, center: miniCenter, outer: size * 0.10, inner: size * 0.035, points: points)

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // Processing dot at bottom-right
            let dotRadius: CGFloat = 2.5
            let dotCenter = CGPoint(x: rect.maxX - dotRadius - 0.5, y: dotRadius + 0.5)
            ctx.addEllipse(in: CGRect(
                x: dotCenter.x - dotRadius,
                y: dotCenter.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Creates 4 animation frames of the sparkle icon rotated at 0/90/180/270 degrees.
    /// Falls back to a single static processing icon when Reduce Motion is enabled.
    static func createAnimationFrames(size: CGFloat = 18) -> [NSImage] {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if reduceMotion {
            return [createProcessingIcon(size: size)]
        }

        let angles: [CGFloat] = [0, .pi / 2, .pi, .pi * 1.5]
        return angles.map { rotation in
            let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

                let center = CGPoint(x: rect.midX, y: rect.midY)
                let outerRadius = size * 0.42
                let innerRadius = size * 0.13
                let points = 4

                // Main 4-pointed star, rotated
                drawStarRotated(in: ctx, center: center, outer: outerRadius, inner: innerRadius, points: points, rotation: rotation)

                // Small accent sparkle at top-right (rotates with main star around center)
                let miniOffset = size * 0.26
                let miniCenter = CGPoint(
                    x: center.x + cos(rotation + .pi / 4) * miniOffset * 1.3,
                    y: center.y + sin(rotation + .pi / 4) * miniOffset * 1.3
                )
                drawStarRotated(in: ctx, center: miniCenter, outer: size * 0.12, inner: size * 0.04, points: points, rotation: rotation)

                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillPath()

                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private static func drawStarRotated(
        in ctx: CGContext,
        center: CGPoint,
        outer: CGFloat,
        inner: CGFloat,
        points: Int,
        rotation: CGFloat
    ) {
        let totalPoints = points * 2
        for i in 0..<totalPoints {
            let radius = i % 2 == 0 ? outer : inner
            let angle = (CGFloat(i) / CGFloat(totalPoints)) * .pi * 2 - .pi / 2 + rotation
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 {
                ctx.move(to: point)
            } else {
                ctx.addLine(to: point)
            }
        }
        ctx.closePath()
    }

    private static func drawStar(
        in ctx: CGContext,
        center: CGPoint,
        outer: CGFloat,
        inner: CGFloat,
        points: Int
    ) {
        drawStarRotated(in: ctx, center: center, outer: outer, inner: inner, points: points, rotation: 0)
    }
}
