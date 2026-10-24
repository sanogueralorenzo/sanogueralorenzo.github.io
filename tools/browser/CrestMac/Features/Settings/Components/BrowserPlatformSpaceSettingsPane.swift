import SwiftUI

/// The Spaces destination on the desktop, where each Space has its own page
/// in the Settings sidebar: the destination opens the requested Space's page.
struct BrowserPlatformSpaceSettingsPane: View {
    @Environment(\.browserSettingsOpenSpace) private var openSpace
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let requestedSpaceID: UUID?
    let requestRevision: Int

    var body: some View {
        Color.clear
            .onAppear {
                guard let id = requestedSpaceID ?? browser.shownSpace?.id else { return }
                openSpace?(id)
            }
    }
}
