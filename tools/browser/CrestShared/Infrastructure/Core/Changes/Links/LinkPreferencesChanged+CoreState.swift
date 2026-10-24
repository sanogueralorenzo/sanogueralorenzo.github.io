import Foundation

extension LinkPreferencesChanged {
    /// The core publishes the link preferences whole.
    @MainActor func apply(to state: CoreState) {
        state.linkPreferences = preferences
    }
}
