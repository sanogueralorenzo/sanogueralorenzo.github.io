import SwiftUI

/// Opens a tab using the hosting sidebar’s input and density preferences.
struct BrowserNewTabRow: View {
    let capabilities: BrowserInteractionCapabilities
    let action: () -> Void

    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    var body: some View {
        BrowserNewTabRowContent(
            capabilities: capabilities, action: action, tabScale: tabScale,
            hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all
        )
    }
}
