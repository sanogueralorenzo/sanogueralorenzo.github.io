import SwiftUI

extension BrowserEngineRegistration {
    /// The WebKit compositions contribute their settings pane here. Chromium
    /// supplies this method from its own engine composition.
    /// WebKit's private runtime feature registry is a Mac-only surface.
    @MainActor @ViewBuilder
    static func featureFlagsPane(space: SpaceModel?, browser: BrowserStore) -> some View {
        #if os(macOS)
            BrowserWebKitFeatureFlagSettingsPane(store: BrowserWebKitFeatureFlagStore.active)
        #endif
    }
}
