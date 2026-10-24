import SwiftUI

/// The native mobile form container for a shared settings pane. The
/// navigation bar carries the page's name in both layouts.
struct BrowserPlatformSettingsPaneContainer<Content: View>: View {
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
        Form {
            content
        }
        .accessibilityIdentifier("settings-form-\(destination.name)")
    }
}
