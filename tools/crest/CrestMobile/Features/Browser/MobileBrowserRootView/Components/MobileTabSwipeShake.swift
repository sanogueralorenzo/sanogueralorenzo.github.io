import SwiftUI

/// Shakes the address bar side to side each time a swipe meets an end of the
/// Space, the way a field refuses what it was given. Reduce Motion keeps the
/// bar still and leaves the haptic to say it.
struct MobileTabSwipeShake: ViewModifier {
    // MARK: - Static Variables

    /// How far the first swing goes, in points; each after it goes less far.
    private static let reach: CGFloat = 10
    /// How long each of the shake's five swings takes.
    private static var swing: TimeInterval { CrestMotion.boundaryShakeTransition / 5 }

    // MARK: - Variables

    let hits: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        let reach = reduceMotion ? 0 : Self.reach
        let swing = Self.swing
        return content.keyframeAnimator(initialValue: CGFloat.zero, trigger: hits) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(reach, duration: swing)
                CubicKeyframe(-reach * 0.8, duration: swing)
                CubicKeyframe(reach * 0.5, duration: swing)
                CubicKeyframe(-reach * 0.3, duration: swing)
                CubicKeyframe(0, duration: swing)
            }
        }
    }
}
