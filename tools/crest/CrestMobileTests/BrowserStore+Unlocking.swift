import Foundation

@testable import CrestMobile

extension BrowserStore {
    /// Unlocks the seeded Space `space` in the core, as the device owner's
    /// authentication does, for a test that shows or edits a protected Space.
    /// The core keeps every protected Space locked until then, whatever the
    /// views believe.
    func unlockForTesting(_ space: SpaceState.Seed) {
        let request = UUID()
        _ = try? core.send(
            BeginUnlockingSpace(workspaceID: family.workspaceID, spaceID: space.id, requestID: request))
        _ = try? core.send(FinishUnlockingSpace(spaceID: space.id, requestID: request, authenticated: true))
    }
}
