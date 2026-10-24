import SwiftUI

struct MobilePageZoomFeedback: View {
    let label: String
    let topPadding: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label(label, systemImage: "textformat.size")
            .font(.callout.weight(.semibold))
            .padding(
                .horizontal,
                MobileBrowserRootLayout.feedbackHorizontalPadding
            )
            .frame(height: MobileBrowserRootLayout.feedbackHeight)
            .glassEffect(.regular, in: .capsule)
            .shadow(
                color: .black.opacity(
                    reduceTransparency ? 0 : CrestOpacity.controlShadow
                ),
                radius: MobileBrowserRootLayout.feedbackShadowRadius,
                y: MobileBrowserRootLayout.feedbackShadowOffset
            )
            .padding(.top, topPadding)
            .allowsHitTesting(false)
            .accessibilityLabel("Page zoom (label)")
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .zIndex(MobileBrowserRootLayout.feedbackLayer)
    }
}

#if DEBUG
    #Preview("Component") {
        MobilePageZoomFeedback(label: "125%", topPadding: 16).frame(width: 390, height: 180)
    }
#endif
