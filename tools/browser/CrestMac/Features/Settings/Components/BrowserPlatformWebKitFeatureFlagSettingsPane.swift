import SwiftUI

/// The desktop-only WebKit runtime feature catalog.
struct BrowserPlatformWebKitFeatureFlagSettingsPane: View {
    var body: some View {
        BrowserWebKitFeatureFlagSettingsPane(
            store: BrowserWebKitFeatureFlagStore.active
        )
    }
}
