import SwiftUI

/// Registers live native bounds for sidebar selection without intercepting input.
struct BrowserPlatformTabSelectionTarget: ViewModifier {
    let itemID: BrowserSelectionItemID?
    let browser: BrowserStore?
    let assignment: BrowserSpaceRuntimeAssignment
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.background {
            if let itemID, let browser, isEnabled {
                BrowserNativeTabSelectionTarget(itemID: itemID, browser: browser, assignment: assignment)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
