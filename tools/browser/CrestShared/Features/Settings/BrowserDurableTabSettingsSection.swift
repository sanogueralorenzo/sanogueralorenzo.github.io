import SwiftUI

struct BrowserDurableTabSettingsSection: View {
    @Bindable var preferences: BrowserAppPreferenceStore

    var body: some View {
        Section("Pinned and saved tabs") {
            Picker("After closing", selection: $preferences.savedTabClosePolicy) {
                ForEach(SavedTabClosePolicy.all, id: \.self) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .accessibilityIdentifier("durable-tab-close-policy")
            #if os(macOS)
                Toggle(
                    "Click the favicon to return to the saved URL", isOn: $preferences.returnsToSavedURLOnFaviconClick
                )
                .accessibilityIdentifier("saved-tab-favicon-root-return")
            #endif
        }
    }
}
