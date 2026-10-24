import SwiftUI

/// The agent's pointer over the page its tab shows: an arrow in the agent's
/// colour with its name beside it, at the point the agent last acted. It
/// glides from one point to the next, ripples where the agent pressed, and
/// fades once the agent pauses. It never takes a click, and Reduce Motion
/// moves it without gliding.
struct BrowserAgentPointerOverlay: View {
    let pointer: BrowserAgentPointer
    let session: AgentSessionState
    /// The page's zoom: the page reports points in its CSS pixels.
    let zoom: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLingering = true
    @State private var presses = 0

    var body: some View {
        let colour = (session.color ?? .agentDefault).color
        ZStack(alignment: .topLeading) {
            Circle()
                .strokeBorder(colour, lineWidth: 2)
                .frame(
                    width: BrowserWebPageSurfaceMetrics.agentPointerRippleSize,
                    height: BrowserWebPageSurfaceMetrics.agentPointerRippleSize
                )
                // At rest the ripple has run out; each press runs it again.
                .keyframeAnimator(initialValue: 1.0, trigger: presses) { ripple, progress in
                    ripple.scaleEffect(0.3 + 0.7 * progress).opacity(1 - progress)
                } keyframes: { _ in
                    LinearKeyframe(0, duration: 0)
                    LinearKeyframe(1, duration: BrowserWebPageSurfaceMetrics.agentPointerRipple)
                }
                .offset(
                    x: -BrowserWebPageSurfaceMetrics.agentPointerRippleSize / 2,
                    y: -BrowserWebPageSurfaceMetrics.agentPointerRippleSize / 2)
            Image(systemName: "cursorarrow")
                .font(.system(size: BrowserWebPageSurfaceMetrics.agentPointerSize, weight: .semibold))
                .foregroundStyle(colour)
                .shadow(radius: 1)
            Text(verbatim: session.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, BrowserWebPageSurfaceMetrics.agentPointerTagHorizontalPadding)
                .padding(.vertical, BrowserWebPageSurfaceMetrics.agentPointerTagVerticalPadding)
                .glassEffect(.regular, in: .capsule)
                .overlay { Capsule().strokeBorder(colour, lineWidth: 1) }
                .offset(BrowserWebPageSurfaceMetrics.agentPointerTagOffset)
        }
        .offset(x: pointer.point.x * zoom, y: pointer.point.y * zoom)
        .animation(
            reduceMotion ? nil : .smooth(duration: BrowserWebPageSurfaceMetrics.agentPointerGlide),
            value: pointer.revision
        )
        .opacity(isLingering ? 1 : 0)
        .animation(.easeOut, value: isLingering)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: pointer.revision) {
            isLingering = true
            if pointer.presses, !reduceMotion { presses &+= 1 }
            // A newer point cancels the wait and keeps the pointer up.
            do { try await Task.sleep(for: BrowserWebPageSurfaceMetrics.agentPointerLinger) } catch { return }
            isLingering = false
        }
    }
}
