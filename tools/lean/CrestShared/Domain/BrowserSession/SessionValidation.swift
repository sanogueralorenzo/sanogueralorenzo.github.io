import Foundation

enum SessionValidation {
    static let emptyID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let maximumSpaces = 64
    static let maximumHistory = 5000

    /// Identity and isolation rules apply in session order, including the refusal precedence.
    static func flaw(_ value: SessionState.Seed) -> SessionFlaw? {
        var spaces: Set<UUID> = []
        var profiles: Set<UUID> = []
        var tabs: Set<UUID> = []
        for space in value.spaces {
            if space.id == emptyID || space.profileID == emptyID || space.tabs.contains(where: { $0.id == emptyID }) {
                return .missingIdentity
            }
            if !spaces.insert(space.id).inserted { return .duplicateSpace }
            if !profiles.insert(space.profileID).inserted { return .sharedProfile }
            for tab in space.tabs where !tabs.insert(tab.id).inserted { return .duplicateTab }
        }
        var pending: Set<UUID> = []
        for deletion in value.spaceDeletions {
            if deletion.id == emptyID || deletion.spaceID == emptyID || deletion.profileID == emptyID {
                return .missingIdentity
            }
            if !pending.insert(deletion.spaceID).inserted
                || !value.spaces.contains(where: { $0.id == deletion.spaceID && $0.profileID == deletion.profileID })
            {
                return .unknownDeletion
            }
        }
        return nil
    }
    static func require(_ value: SessionState.Seed) throws {
        if let flaw = flaw(value) { throw Rejection.invalidSession(InvalidSession(flaw: flaw)) }
    }
}
