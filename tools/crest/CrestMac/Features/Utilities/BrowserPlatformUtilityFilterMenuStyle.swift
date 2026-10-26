import SwiftUI

/// macOS renders the utility filter as native borderless menu chrome.
struct BrowserPlatformUtilityFilterMenuStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.menuStyle(.borderlessButton)
    }
}
