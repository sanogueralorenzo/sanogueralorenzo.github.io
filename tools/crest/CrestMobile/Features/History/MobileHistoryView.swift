import SwiftUI

struct MobileHistoryView: View {
    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment
    let spaceAccess: BrowserSpaceAccessController
    let openURL: (URL) -> Void

    var body: some View {
        MobileHistoryContent(
            space: space,
            clearHistory: clearHistory,
            openURL: openCapturedURL
        )
        .presentationDetents([.medium, .large])
    }

    private var space: SpaceModel? {
        browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess)
    }

    private func clearHistory() {
        guard space != nil else { return }
        browser.clearHistory(matching: assignment)
    }

    private func openCapturedURL(_ url: URL) {
        guard space != nil else { return }
        openURL(url)
    }
}
