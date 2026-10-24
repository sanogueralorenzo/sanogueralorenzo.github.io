import SwiftUI

/// The desktop's rebindable command table.
struct BrowserPlatformShortcutSettingsPane: View {
    let shortcuts: BrowserShortcutStore
    let requestedSpaceID: UUID?
    let requestRevision: Int

    var body: some View {
        BrowserShortcutSettingsView(
            shortcuts: shortcuts,
            requestedSpaceID: requestedSpaceID,
            requestRevision: requestRevision
        )
    }
}
