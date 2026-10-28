import SwiftUI

extension View {
    /// Pins a custom control's keyboard focus ring to the authored shape.
    func crestFocusShape(_ shape: some Shape) -> some View {
        modifier(CrestPlatformFocusShapeModifier(shape: shape))
    }

    func crestCapsuleInteractionShape() -> some View {
        contentShape(.capsule)
            .crestFocusShape(Capsule())
    }

    /// Shared press acknowledgement, disabled treatment, and Reduce Motion gate.
    func crestPressFeedback(isPressed: Bool, isEnabled: Bool) -> some View {
        modifier(
            CrestPressFeedbackModifier(
                isPressed: isPressed,
                isEnabled: isEnabled
            )
        )
    }
}
