import SwiftUI

struct CrestPressFeedbackModifier: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                (isPressed ? CrestButtonMetrics.pressedScale : 1).unlessReducingMotion(reduceMotion)
            )
            .opacity(isEnabled ? 1 : CrestButtonMetrics.disabledOpacity)
            .animation(
                CrestMotion.press.unlessReducingMotion(reduceMotion),
                value: isPressed
            )
    }
}
