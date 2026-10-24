import SwiftUI

/// Touch's Spaces pane: one Space at a time, chosen from a picker.
///
/// Nothing on touch routes a particular Space into Settings the way the
/// desktop's sidebar does, so the requested Space arrives and goes unread.
///
/// The desktop gives each Space its own pages in the Settings sidebar; here
/// one scrolling pane holds ``BrowserSpaceSettingsSections``.
struct BrowserPlatformSpaceSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let requestedSpaceID: UUID?
    let requestRevision: Int

    var body: some View {
        MobileSpaceSettingsView(
            browser: browser,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter
        )
    }
}
