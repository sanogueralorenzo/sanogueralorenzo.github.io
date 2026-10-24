import SwiftUI

/// The dashed "one more" chip.
struct CrestSpaceAddChipStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        CrestSpaceAddChipSurface(
            tint: tint,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
    }
}
