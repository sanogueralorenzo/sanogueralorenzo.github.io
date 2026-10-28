import SwiftUI

/// iPadOS has no column-resize pointer shape to ask for — SwiftUI's
/// `PointerStyle` is explicitly unavailable on iOS — so the divider takes the
/// platform's own targetable-element treatment instead: an indirect pointer
/// morphs onto the handle as it passes over.
///
/// Touch input and iPhone see nothing, which is the correct outcome rather than
/// a missing one. There is no pointer there to inform, and the handle's own
/// hit width already makes it reachable by finger.
struct BrowserPlatformColumnResizePointerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.hoverEffect(.highlight)
    }
}
