import SwiftUI

/// UIKit's drag interaction arbitrates with context menus and supplies the lift preview.
struct BrowserPlatformSidebarReorderLiftGesture: ViewModifier {
    var isEnabled = true
    /// Takes the pointer moving a lift, from where it began to where it is.
    let moved: (_ startLocation: CGPoint, _ location: CGPoint) -> Void
    /// Takes the pointer letting go.
    let released: () -> Void

    func body(content: Content) -> some View { content }
}
