import Foundation

@testable import Crest

@MainActor
final class SuspendingBrowserSpaceDataDeleter: BrowserSpaceDataDeleting {
    private let core: CrestCore
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var deletionContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    init(core: CrestCore) {
        self.core = core
    }

    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            deletionContinuation = continuation
        }
        try await core.eraseProfile(of: space)
    }

    func waitUntilDeletionStarts() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishDeletion() {
        deletionContinuation?.resume()
        deletionContinuation = nil
    }
}
