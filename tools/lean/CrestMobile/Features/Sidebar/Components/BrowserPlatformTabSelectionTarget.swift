import SwiftUI

/// Mobile has no native sidebar selection target to register.
struct BrowserPlatformTabSelectionTarget: ViewModifier {
    let itemID: BrowserSelectionItemID?
    let browser: BrowserStore?
    let assignment: BrowserSpaceRuntimeAssignment
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
    }
}
