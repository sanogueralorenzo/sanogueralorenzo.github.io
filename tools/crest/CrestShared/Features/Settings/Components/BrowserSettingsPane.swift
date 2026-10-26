import SwiftUI

/// Shared sections use an adaptive canvas in browser tabs and a grouped Form
/// in compact Settings sheets, without duplicating preference bindings.
struct BrowserSettingsPane<Content: View>: View {
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    init(
        _ destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        BrowserPlatformSettingsPaneContainer(destination: destination) {
            content
        }
    }
}
