import Foundation

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

    @MainActor
    init?(for space: SpaceModel, in browser: BrowserStore) {
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard browser.selectedAvailableSpace(matching: assignment) != nil
        else { return nil }
        self.init(assignment: assignment, spaceName: space.settings.name)
    }

    // MARK: - Actions - Clearing

    @MainActor
    func isLive(in browser: BrowserStore) -> Bool {
        browser.selectedAvailableSpace(matching: assignment) != nil
    }

    @MainActor
    @discardableResult
    func clearHistory(in browser: BrowserStore) -> Bool {
        guard isLive(in: browser) else { return false }
        return browser.clearHistory(matching: assignment)
    }
}
