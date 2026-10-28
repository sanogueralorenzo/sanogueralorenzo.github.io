import Foundation

extension EnginePreferencesChanged {
    @MainActor func apply(to state: CoreState) {
        state.enginePreferences = preferences
    }
}
