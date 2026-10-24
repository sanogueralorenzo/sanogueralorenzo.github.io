import Observation

@Observable
@MainActor
final class BrowserTabDragState {
    /// Clears a provider or drag session that never receives native completion.
    nonisolated static let sessionExpiration: Duration = .seconds(30)

    /// Give a destination's synchronous `performDrop` callback time to finish
    /// before treating the touch release as a cancelled/outside drop.
    nonisolated static let releaseCleanupDelay: Duration = .milliseconds(180)

    private(set) var item: BrowserTabDragItem?
    private(set) var sessionToken: BrowserDragSessionToken?
    private(set) var sourcePlacement: TabPlacement?
    private(set) var currentPlacement: TabPlacement?
    private(set) var dropLocation: BrowserTabDropLocation?
    private(set) var liveMoveCount = 0
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private var deferredLeaveTask: Task<Void, Never>?
    @ObservationIgnored private var releaseCleanupTask: Task<Void, Never>?
    @ObservationIgnored private var nextSessionGeneration: UInt64 = 0

    @discardableResult
    func begin(
        item: BrowserTabDragItem,
        placement: TabPlacement
    ) -> BrowserDragSessionToken {
        expirationTask?.cancel()
        deferredLeaveTask?.cancel()
        releaseCleanupTask?.cancel()
        nextSessionGeneration &+= 1
        let token = BrowserDragSessionToken(
            generation: nextSessionGeneration
        )
        self.item = item
        sessionToken = token
        sourcePlacement = placement
        currentPlacement = placement
        dropLocation = nil
        liveMoveCount = 0
        expirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserTabDragState.sessionExpiration)
            guard !Task.isCancelled else { return }
            self?.end(session: token)
        }
        return token
    }

    /// Whether the drop indicator at `location` shows: a row drop, not a grid
    /// one, aimed there by a drag in flight.
    func showsDropIndicator(at location: BrowserTabDropLocation) -> Bool {
        !location.placement.isGrid
            && item != nil
            && dropLocation == location
    }

    func isDragging(_ item: BrowserTabDragItem) -> Bool {
        self.item == item
    }

    func isDragging(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        item?.runtimeAssignment == assignment
    }

    @discardableResult
    func enter(_ location: BrowserTabDropLocation) -> Bool {
        deferredLeaveTask?.cancel()
        deferredLeaveTask = nil
        guard item != nil, dropLocation != location else { return false }
        dropLocation = location
        currentPlacement = location.placement
        return true
    }

    func leave(
        _ location: BrowserTabDropLocation,
        restoringSourcePlacement: Bool = false
    ) {
        guard dropLocation == location else { return }
        dropLocation = nil
        guard restoringSourcePlacement, let sourcePlacement else { return }
        let placement = BrowserTabDragPreviewLayout.outsidePinnedPlacement(
            for: sourcePlacement
        )
        currentPlacement = placement
    }

    func relocate(to assignment: BrowserSpaceRuntimeAssignment) {
        guard let item,
            item.spaceID != assignment.spaceID
                || item.profileID != assignment.profileID
        else { return }
        self.item = BrowserTabDragItem(
            tabID: item.tabID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    func end() {
        expirationTask?.cancel()
        expirationTask = nil
        deferredLeaveTask?.cancel()
        deferredLeaveTask = nil
        releaseCleanupTask?.cancel()
        releaseCleanupTask = nil
        item = nil
        sessionToken = nil
        sourcePlacement = nil
        currentPlacement = nil
        dropLocation = nil
    }

    func end(session token: BrowserDragSessionToken) {
        guard sessionToken == token else { return }
        end()
    }

    func end(ifDragging item: BrowserTabDragItem) {
        guard isDragging(item) else { return }
        end()
    }

    func contextMenuDidOpen(for assignment: BrowserTabRuntimeAssignment) {
        guard isDragging(assignment) else { return }
        end()
    }

    func contextMenuDidClose(for assignment: BrowserTabRuntimeAssignment) {
        guard isDragging(assignment) else { return }
        end()
    }

    func endAfterTouchRelease() {
        guard let sessionToken else { return }
        endAfterTouchRelease(session: sessionToken)
    }

    func endAfterTouchRelease(session token: BrowserDragSessionToken) {
        guard sessionToken == token else { return }
        releaseCleanupTask?.cancel()
        releaseCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserTabDragState.releaseCleanupDelay)
            guard !Task.isCancelled, let self else { return }
            releaseCleanupTask = nil
            end(session: token)
        }
    }
}
