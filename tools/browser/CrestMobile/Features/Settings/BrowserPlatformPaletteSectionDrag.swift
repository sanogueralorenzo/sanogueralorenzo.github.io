import SwiftUI

/// The palette's sections reorder with the form's own drag on iPhone and
/// iPad, so a row adds nothing of its own.
struct BrowserPlatformPaletteSectionDrag: ViewModifier {
    let source: PaletteSource
    @Binding var dragged: PaletteSource?
    let move: (PaletteSource, PaletteSource) -> Void

    func body(content: Content) -> some View {
        content
    }
}
