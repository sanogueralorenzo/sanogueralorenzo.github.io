import Foundation

@MainActor
struct BrowserGitHubFolderAction {
    // MARK: - Variables

    let browser: BrowserStore
    let assignment: BrowserSpaceRuntimeAssignment

    // MARK: - Actions - Creation

    @discardableResult
    func create() -> UUID? {
        guard !browser.isPrivateBrowsing,
            let space = browser.selectedAvailableSpace(matching: assignment)
        else { return nil }
        let id = space.folders.models.first(where: { $0.source == .gitHubPullRequests })?.id ?? UUID()
        let creation = EnableGitHubLiveFolder(
            workspaceID: browser.family.workspaceID, spaceID: assignment.spaceID, profileID: assignment.profileID,
            folderID: id)
        guard browser.family.perform(creation, from: browser) != nil else { return nil }
        browser.setFolderCollapsed(id, matching: assignment, isCollapsed: false)
        return id
    }
}
