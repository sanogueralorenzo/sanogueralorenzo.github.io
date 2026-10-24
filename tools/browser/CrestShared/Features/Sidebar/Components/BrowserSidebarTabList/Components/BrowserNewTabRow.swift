import SwiftUI

/// Opens a tab using the hosting sidebar’s input and density preferences.
struct BrowserNewTabRow: View {
    let capabilities: BrowserInteractionCapabilities
    let action: () -> Void

    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0

    var body: some View {
        BrowserNewTabRowContent(
            capabilities: capabilities, action: action, tabScale: tabScale,
            hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all
        )
    }
}
