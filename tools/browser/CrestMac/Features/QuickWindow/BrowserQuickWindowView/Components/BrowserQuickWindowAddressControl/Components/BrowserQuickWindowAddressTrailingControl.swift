import SwiftUI

struct BrowserQuickWindowAddressTrailingControl: View {
    let page: BrowserPage?
    @Binding var addressText: String
    let isAddressEditing: Bool
    let reloadOrStop: () -> Void

    var body: some View {
        Group {
            if isAddressEditing, !addressText.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    addressText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            } else if let page {
                BrowserReloadControl(
                    isLoading: page.live.isLoading,
                    isDeveloperMode: page.isDeveloperModeEnabled,
                    reloadOrStop: reloadOrStop,
                    reload: { page.performReload(.standard) },
                    reloadFromOrigin: { page.performReload(.fromOrigin) },
                    clearSiteDataAndReload: page.clearSiteDataAndReload
                )
            }
        }
    }
}
