import SwiftUI

/// The native macOS grouped form for a shared settings pane: one centred
/// column of rows.
///
/// The column is placed by ``BrowserSettingsColumnLayout``, a computed margin
/// from the page's leading edge. With horizontal scroll margins instead, macOS
/// 26 placed the rows' clicks and accessibility frames a margin away from where
/// it drew them.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
    @Environment(\.browserSettingsTabState) private var tabState
    @Environment(\.browserSettingsScrollKey) private var scrollKey
    @Environment(\.browserSettingsColumnWidth) private var columnWidth
    @State private var standaloneScroll = BrowserNativeScrollState()
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    init(
        destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        BrowserSettingsColumnLayout(columnWidth: columnWidth ?? BrowserSettingsLayout.formColumnWidth) {
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .browserNativeScrollState(tabState?.scroll(forKey: scrollKey ?? destination.name) ?? standaloneScroll)
        }
        .accessibilityIdentifier("settings-form-\(destination.name)")
    }
}
