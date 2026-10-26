import Foundation

/// The pull of the staged Peek `requestID` names was cancelled.
struct BrowserPeekDragCancelled: BrowserPeekInteractionEvent {
    // MARK: - Variables

    let requestID: UUID

    // MARK: - Actions - Peeks

    @MainActor
    func apply(to coordinator: BrowserTransientBrowsingCoordinator) {
        coordinator.cancelStagedPeek(id: requestID)
    }
}
