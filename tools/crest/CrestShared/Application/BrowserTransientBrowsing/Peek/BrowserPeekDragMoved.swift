import Foundation

/// The pull of the staged Peek `requestID` names moved to `state`.
struct BrowserPeekDragMoved: BrowserPeekInteractionEvent {
    // MARK: - Variables

    let requestID: UUID
    let state: BrowserPeekMotionState

    // MARK: - Actions - Peeks

    @MainActor
    func apply(to coordinator: BrowserTransientBrowsingCoordinator) {
        coordinator.updatePeekDrag(id: requestID, state: state)
    }
}
