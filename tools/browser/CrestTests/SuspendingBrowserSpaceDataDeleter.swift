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

extension CrestCore {
    /// Has every engine erase the profile of the Space `space` names, which
    /// keeps nothing on disk in a test, as the app's deleter does before the
    /// Space may go.
    func eraseProfile(of space: BrowserSpaceRuntimeAssignment) async throws {
        guard await deleteData(DeleteProfileData(requestID: UUID(), profileID: space.profileID, ephemeral: true))
        else { throw BrowserSpaceDeletionError.dataNotErased }
    }
}
