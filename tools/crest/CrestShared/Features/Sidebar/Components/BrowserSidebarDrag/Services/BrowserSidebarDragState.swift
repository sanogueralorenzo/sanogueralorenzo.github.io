import Observation

/// The sidebar row a drag lifted, folder or tab, and the session that lifted
/// it, which ends when the drop lands, a context menu takes over, the touch
/// lets go somewhere that takes nothing, or the system never completes it.
@Observable
@MainActor
final class BrowserSidebarDragState<Item: Equatable> {
    // MARK: - Static Variables

    /// Clears a provider or drag session that never receives native completion.
    nonisolated static var sessionExpiration: Duration { .seconds(30) }

    /// Give a destination's synchronous `performDrop` callback time to finish
    /// before treating the touch release as a cancelled/outside drop.
    nonisolated static var releaseCleanupDelay: Duration { .milliseconds(180) }

    // MARK: - Variables

    private(set) var item: Item?
    private(set) var sessionToken: BrowserDragSessionToken?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private var releaseCleanupTask: Task<Void, Never>?
    @ObservationIgnored private var nextSessionGeneration: UInt64 = 0

    // MARK: - Actions - Session

    @discardableResult
    func begin(item: Item) -> BrowserDragSessionToken {
        expirationTask?.cancel()
        releaseCleanupTask?.cancel()
        nextSessionGeneration &+= 1
        let token = BrowserDragSessionToken(
            generation: nextSessionGeneration
        )
        self.item = item
        sessionToken = token
        expirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.sessionExpiration)
            guard !Task.isCancelled else { return }
            self?.end(session: token)
        }
        return token
    }

    func isDragging(_ item: Item) -> Bool {
        self.item == item
    }

    func end() {
        expirationTask?.cancel()
        expirationTask = nil
        releaseCleanupTask?.cancel()
        releaseCleanupTask = nil
        item = nil
        sessionToken = nil
    }

    func end(session token: BrowserDragSessionToken) {
        guard sessionToken == token else { return }
        end()
    }

    func end(ifDragging item: Item) {
        guard isDragging(item) else { return }
        end()
    }

    func contextMenuDidOpen(for item: Item) {
        end(ifDragging: item)
    }

    func contextMenuDidClose(for item: Item) {
        end(ifDragging: item)
    }

    func endAfterTouchRelease() {
        guard let sessionToken else { return }
        endAfterTouchRelease(session: sessionToken)
    }

    func endAfterTouchRelease(session token: BrowserDragSessionToken) {
        guard sessionToken == token else { return }
        releaseCleanupTask?.cancel()
        releaseCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.releaseCleanupDelay)
            guard !Task.isCancelled, let self else { return }
            releaseCleanupTask = nil
            end(session: token)
        }
    }
}

typealias BrowserFolderDragState = BrowserSidebarDragState<BrowserFolderDragItem>
typealias BrowserTabDragState = BrowserSidebarDragState<BrowserTabDragItem>

/// A lifted tab is known by its Space and profile as well, and follows its
/// tab when a drop moves it to another Space.
extension BrowserSidebarDragState where Item == BrowserTabDragItem {
    // MARK: - Actions - Session

    func isDragging(_ assignment: BrowserTabRuntimeAssignment) -> Bool {
        item?.runtimeAssignment == assignment
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

    func contextMenuDidOpen(for assignment: BrowserTabRuntimeAssignment) {
        guard isDragging(assignment) else { return }
        end()
    }

    func contextMenuDidClose(for assignment: BrowserTabRuntimeAssignment) {
        guard isDragging(assignment) else { return }
        end()
    }
}
