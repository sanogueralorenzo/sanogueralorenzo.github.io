import SwiftUI

/// A sidebar row's auxiliary-button click, which a touch shell has no way to
/// deliver: there is no third button under a finger, and the actions a middle
/// click reaches on macOS are already on the row's context menu here.
///
/// The action is still accepted so the shared row can hand over the same
/// closure on both platforms; nothing on this side calls it.
struct BrowserPlatformRowAuxiliaryClickModifier: ViewModifier {
    var perform: (@MainActor () -> Void)?

    func body(content: Content) -> some View {
        content
    }
}
