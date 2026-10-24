import SwiftUI

/// Uses the same selected palette and system appearance as the Dock icon.
struct BrowserPlatformCurrentAppIcon: View {
    @AppStorage(BrowserMacAppIconAssets.preferenceKey, store: BrowserMacDockTile.shared.defaults)
    private var selectedName = ""
    @State private var appearanceRevision = 0
    @State private var appearanceObserver: BrowserMacAppIconAppearanceObserver?

    var body: some View {
        Image(
            nsImage: BrowserMacAppIconAssets.image(named: selectedName, in: .main)
                ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        )
        .resizable()
        .scaledToFit()
        .id(appearanceRevision)
        .onAppear {
            appearanceObserver = BrowserMacAppIconAppearanceObserver { appearanceRevision += 1 }
        }
        .onDisappear {
            appearanceObserver?.stop()
            appearanceObserver = nil
        }
    }
}
