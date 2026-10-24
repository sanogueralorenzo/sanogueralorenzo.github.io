#if CREST_CHROMIUM_HOST
    import SwiftUI

    extension BrowserEngineRegistration {
        /// Selected by the process composition, never by synced Space records.
        static var current: BrowserAdapterRegistration { chromium }

        /// The default engine's flags. Settings opens its flags page on the
        /// default engine, so with WebKit as the default Chromium's page could
        /// not load there and WebKit's own runtime features show instead.
        @MainActor @ViewBuilder
        static func featureFlagsPane(space: SpaceModel?, browser: BrowserStore) -> some View {
            if browser.core.state.engines?.engines.first(where: \.isDefault)?.kind == .webKit {
                BrowserPlatformWebKitFeatureFlagSettingsPane()
            } else {
                BrowserChromiumFeatureFlagSettingsPane(space: space, browser: browser)
            }
        }
    }
#endif
