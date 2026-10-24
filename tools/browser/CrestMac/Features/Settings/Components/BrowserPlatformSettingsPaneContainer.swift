import SwiftUI

/// The native macOS grouped form for a shared settings pane: one centred
/// column of rows.
///
/// The column is placed by its frame, a computed margin from the page's
/// leading edge. With horizontal scroll margins instead, macOS 26 placed the
/// rows' clicks and accessibility frames a margin away from where it drew them.
/// A column whose rows need more than the page, such as the Crest Studio's in a
/// narrow window, runs past the trailing edge, never over the Settings sidebar.
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
        GeometryReader { geometry in
            let inset = BrowserSettingsLayout.formInset(
                for: geometry.size.width, columnWidth: columnWidth ?? BrowserSettingsLayout.formColumnWidth)
            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .browserNativeScrollState(tabState?.scroll(forKey: scrollKey ?? destination.name) ?? standaloneScroll)
            .frame(width: max(0, geometry.size.width - 2 * inset), alignment: .leading)
            .padding(.leading, inset)
        }
        .accessibilityIdentifier("settings-form-\(destination.name)")
    }
}
