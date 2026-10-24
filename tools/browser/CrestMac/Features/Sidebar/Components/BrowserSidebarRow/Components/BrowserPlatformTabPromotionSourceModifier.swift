import SwiftUI

/// Marks a row as the place the page zooms out of when its tab is selected —
/// which a windowed shell never does: the page is already on screen beside the
/// sidebar, so selecting a tab swaps content rather than pushing a new view.
///
/// The arguments are still accepted so the shared row can pass the same values
/// on both platforms; nothing on this side reads them.
struct BrowserPlatformTabPromotionSourceModifier: ViewModifier {
    let id: String
    var namespace: Namespace.ID?
    var usesNativeNavigationTransition = false
    var isEnabled = true

    func body(content: Content) -> some View {
        content
    }
}
