import SwiftUI

/// Marks a row as the place the page zooms out of when its tab is selected.
///
/// The compact shell pushes the page over the sidebar, so where that push is the
/// system's own navigation zoom the row is a real transition source. That is the
/// whole of what this seam supplies — the matched-geometry end of a promotion is
/// the shared row's decision, and a seam that answered for it as well left one
/// identity carrying two anchors. See `mobileTabTransitionSource`.
struct BrowserPlatformTabPromotionSourceModifier: ViewModifier {
    let id: String
    var namespace: Namespace.ID?
    var usesNativeNavigationTransition = false
    var isEnabled = true

    func body(content: Content) -> some View {
        content.mobileTabTransitionSource(
            id: id,
            in: namespace,
            usesNativeNavigationTransition: usesNativeNavigationTransition,
            isEnabled: isEnabled
        )
    }
}
