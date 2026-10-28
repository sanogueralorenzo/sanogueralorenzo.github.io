import SwiftUI

/// macOS owns a real column-resize pointer, so the divider can say what it does
/// before anyone grabs it.
///
/// `pointerStyle(_:)` and `PointerStyle.columnResize` are macOS 15 and later,
/// well under Crest's macOS 26.1 deployment target, so the affordance needs no
/// availability fork of its own — only the platform fork this file is.
struct BrowserPlatformColumnResizePointerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.pointerStyle(.columnResize)
    }
}
