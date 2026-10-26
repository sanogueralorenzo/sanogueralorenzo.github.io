import SwiftUI

/// A Space chip. Exposed because the onboarding wizard's absorbed chip style
/// forwards to it.
struct CrestSpaceChipStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        CrestSpaceChipSurface(
            tint: tint,
            isSelected: isSelected,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
    }
}
