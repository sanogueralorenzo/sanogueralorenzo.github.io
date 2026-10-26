import Foundation

extension SpaceLockChanged {
    /// A Space profile that holds no grant and waits on nobody leaves the map.
    @MainActor func apply(to state: CoreState) {
        var access = state.spaceAccessStorage
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID, profileID: profileID)
        access[assignment] = isUnlocked || isAuthenticating ? self : nil
        state.publish(access, into: \.spaceAccessStorage, as: \.spaceAccess)
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.notificationAccessChanged = true
        apply(to: core.state)
    }
}
