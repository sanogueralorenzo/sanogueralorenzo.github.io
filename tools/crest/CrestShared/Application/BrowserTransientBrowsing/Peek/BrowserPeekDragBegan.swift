/// A pull out of a link began, staging a Peek of `request` at `state`.
struct BrowserPeekDragBegan: BrowserPeekInteractionEvent {
    // MARK: - Variables

    let request: BrowserPeekRequest
    let state: BrowserPeekMotionState

    // MARK: - Actions - Peeks

    @MainActor
    func apply(to coordinator: BrowserTransientBrowsingCoordinator) {
        coordinator.beginPeekDrag(request, state: state)
    }
}
