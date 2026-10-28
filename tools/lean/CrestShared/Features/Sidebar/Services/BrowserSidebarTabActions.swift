import Foundation

@MainActor
struct BrowserSidebarTabActions {
    let assignment: BrowserSpaceRuntimeAssignment
    private let reorderState: BrowserSidebarReorderState
    let browser: BrowserStore

    /// Brings the page layer back in step with a session this type just
    /// rewrote. The windowed shell reconciles its pool and re-presents the
    /// selection; the compact shell has nothing to do.
    private let syncPagesAfterMutation: @MainActor () -> Void

    init(
        assignment: BrowserSpaceRuntimeAssignment,
        browser: BrowserStore,
        reorderState: BrowserSidebarReorderState,
        syncPagesAfterMutation: @escaping @MainActor () -> Void
    ) {
        self.assignment = assignment
        self.browser = browser
        self.reorderState = reorderState
        self.syncPagesAfterMutation = syncPagesAfterMutation
    }

    /// Closes the Space's current tabs, leaving its pinned and saved tabs be.
    @discardableResult
    func clearCurrentTabs() -> Bool {
        guard
            browser.selectedAvailableSpace(matching: assignment) != nil,
            browser.clearCurrentTabs(matching: assignment)
        else { return false }
        syncPagesAfterMutation()
        return true
    }

    /// Routes an empty-background gesture through the host's existing New Tab
    /// command. Recheck ownership when the gesture ends, after any Space change.
    @discardableResult
    func openNewTab(_ command: () -> Void) -> Bool {
        guard !reorderState.isDragging,
            browser.selectedAvailableSpace(matching: assignment) != nil
        else { return false }
        command()
        return true
    }
}
