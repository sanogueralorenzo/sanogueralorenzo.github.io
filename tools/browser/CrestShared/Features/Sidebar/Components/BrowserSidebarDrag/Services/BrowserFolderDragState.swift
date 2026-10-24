import Observation

@Observable
@MainActor
final class BrowserFolderDragState {
    private(set) var item: BrowserFolderDragItem?
    private(set) var sessionToken: BrowserDragSessionToken?
    private(set) var dropLocation: BrowserFolderDropLocation?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?
    @ObservationIgnored private var releaseCleanupTask: Task<Void, Never>?
    @ObservationIgnored private var nextSessionGeneration: UInt64 = 0

    @discardableResult
    func begin(item: BrowserFolderDragItem) -> BrowserDragSessionToken {
        expirationTask?.cancel()
        releaseCleanupTask?.cancel()
        nextSessionGeneration &+= 1
        let token = BrowserDragSessionToken(
            generation: nextSessionGeneration
        )
        self.item = item
        sessionToken = token
        dropLocation = nil
        expirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserTabDragState.sessionExpiration)
            guard !Task.isCancelled else { return }
            self?.end(session: token)
        }
        return token
    }

    func isDragging(_ item: BrowserFolderDragItem) -> Bool {
        self.item == item
    }

    @discardableResult
    func enter(_ location: BrowserFolderDropLocation) -> Bool {
        guard item != nil, dropLocation != location else { return false }
        dropLocation = location
        return true
    }

    func leave(_ location: BrowserFolderDropLocation) {
        guard dropLocation == location else { return }
        dropLocation = nil
    }

    func end() {
        expirationTask?.cancel()
        expirationTask = nil
        releaseCleanupTask?.cancel()
        releaseCleanupTask = nil
        item = nil
        sessionToken = nil
        dropLocation = nil
    }

    func end(session token: BrowserDragSessionToken) {
        guard sessionToken == token else { return }
        end()
    }

    func end(ifDragging item: BrowserFolderDragItem) {
        guard isDragging(item) else { return }
        end()
    }

    func contextMenuDidOpen(for item: BrowserFolderDragItem) {
        end(ifDragging: item)
    }

    func contextMenuDidClose(for item: BrowserFolderDragItem) {
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
            try? await Task.sleep(for: BrowserTabDragState.releaseCleanupDelay)
            guard !Task.isCancelled, let self else { return }
            releaseCleanupTask = nil
            end(session: token)
        }
    }
}
