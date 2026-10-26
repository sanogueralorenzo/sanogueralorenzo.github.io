import SwiftUI

/// Mobile keeps the utility filter's menu trigger visually plain.
struct BrowserPlatformUtilityFilterMenuStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.plain)
    }
}
