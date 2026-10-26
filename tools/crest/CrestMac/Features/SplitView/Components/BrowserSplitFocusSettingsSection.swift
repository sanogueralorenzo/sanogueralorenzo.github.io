import SwiftUI

/// The Split View focus preference, in the Tabs settings pane.
struct BrowserSplitFocusSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    var body: some View {
        Section("Split View") {
            Toggle("Focus follows pointer", isOn: $preferences.splitFocusFollowsMouse)
        }
    }
}
