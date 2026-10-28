import SwiftUI

struct BrowserCommandPaletteShellMaterial: ViewModifier {
    let shape: RoundedRectangle
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.background, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
