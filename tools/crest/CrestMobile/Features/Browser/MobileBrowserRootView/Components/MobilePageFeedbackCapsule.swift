import SwiftUI

/// A transient capsule at the top of the page that reports what an action
/// did, such as a zoom change or a cleared site. It asks nothing of the person.
struct MobilePageFeedbackCapsule: View {
    let feedback: MobilePageFeedback
    let topPadding: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label(feedback.label, systemImage: feedback.systemImage)
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
            .accessibilityLabel(feedback.accessibilityLabel)
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
        MobilePageFeedbackCapsule(feedback: .pageZoom("125%"), topPadding: 16).frame(width: 390, height: 180)
    }
#endif
