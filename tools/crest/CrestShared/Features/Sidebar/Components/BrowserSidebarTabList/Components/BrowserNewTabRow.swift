import SwiftUI

/// Opens a tab using the hosting sidebar’s input and density preferences.
struct BrowserNewTabRow: View {
    let capabilities: BrowserInteractionCapabilities
    let action: () -> Void

    private let tabScale = 1.0

    var body: some View {
        BrowserNewTabRowContent(
            capabilities: capabilities, action: action, tabScale: tabScale,
            hasBorders: false
        )
    }
}
