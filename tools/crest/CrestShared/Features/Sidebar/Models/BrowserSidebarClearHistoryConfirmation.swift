import Foundation

/// A pending request to clear one Space's history, which stays good only while
/// that Space is the window's selected, unlocked Space.
struct BrowserSidebarClearHistoryConfirmation: Equatable, Sendable {
    // MARK: - Variables

    let assignment: BrowserSpaceRuntimeAssignment
    let spaceName: String

    var spaceID: UUID { assignment.spaceID }

    // MARK: - Initializers

    init(assignment: BrowserSpaceRuntimeAssignment, spaceName: String) {
        self.assignment = assignment
        self.spaceName = spaceName
    }

    /// The confirmation for clearing `space`'s history, or nil when `browser`
    /// does not show it selected and unlocked.
    @MainActor
    init?(for space: SpaceModel, in browser: BrowserStore, accessController: BrowserSpaceAccessController) {
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard browser.selectedUnlockedSpace(matching: assignment, accessController: accessController) != nil
        else { return nil }
        self.init(assignment: assignment, spaceName: space.settings.name)
    }

    // MARK: - Actions - Clearing

    @MainActor
    func isLive(in browser: BrowserStore, accessController: BrowserSpaceAccessController) -> Bool {
        browser.selectedUnlockedSpace(matching: assignment, accessController: accessController) != nil
    }

    @MainActor
    @discardableResult
    func clearHistory(in browser: BrowserStore, accessController: BrowserSpaceAccessController) -> Bool {
        guard isLive(in: browser, accessController: accessController) else { return false }
        return browser.clearHistory(matching: assignment)
    }
}
