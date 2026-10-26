import SwiftUI

/// A Space chip. Its label-only style
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
