import SwiftUI

struct MobileArchiveView: View {
    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (UUID) -> Void

    var body: some View {
        MobileArchiveContent(
            space: space,
            favicons: browser.core.state.favicons,
            restoreArchivedTab: restoreArchivedTab
        )
        .presentationDetents([.medium, .large])
    }

    private func restoreArchivedTab(_ tabID: UUID) {
        guard space != nil,
            browser.restoreArchivedTab(tabID, matching: assignment)
        else { return }
        selectTab(tabID)
    }

    private var space: SpaceModel? {
        browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
    }
}
