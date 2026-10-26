import SwiftUI

/// Whether holding a Most Recent Tab shortcut shows the recent tabs, in the
/// Tabs settings pane.
struct BrowserRecentTabsSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section("Switching") {
            Toggle("Show recent tabs while switching", isOn: $preferences.showsRecentTabs)
        }
    }
}
