import Foundation

extension SessionMutations {
    func freshSpace(_ id: UUID, number: Int) -> SpaceState.Seed {
        let name = kind.isPrivate ? (number == 1 ? "Private" : "Private \(number)") : "Space \(number)"
        return SpaceState.Seed(
            id: id, profileID: ids(), name: name, tabs: [.startPage(id: ids(), lastActivatedAt: now)],
            color: SpaceColor.all[(number - 1) % SpaceColor.all.count])
    }
    func deletion(_ id: UUID) throws -> (SpaceState.Seed, SpaceDeletionState?) {
        guard let value = basis.spaces.first(where: { $0.id == id }) else {
            throw Rejection.unknownSpace(UnknownSpace(spaceID: id))
        }
        return (value, basis.spaceDeletions.first { $0.spaceID == id })
    }
    func removable(_ count: Int) throws {
        guard count > 1 else { throw Rejection.cannotDeleteLastSpace(CannotDeleteLastSpace()) }
    }
    func spaceEdit(_ request: some SessionIntent) throws -> SessionMutation? {
        switch request {
        case let request as SetAppPreferences:
            try requirePreferences()
            var next = basis
            next.appPreferences = request.preferences
            return SessionMutation(session: next, stage: nil)
        case let request as SetSpaceIdentity:
            try requireOwnedSpaces()
            var value = try space(request.spaceID)
            let trimmed = BrowserAddress.trimmed(request.name)
            let name = trimmed.isEmpty ? "Untitled Space" : trimmed
            guard name.utf16.count <= SessionTabs.maximumNameLength else {
                throw Rejection.invalidName(InvalidName(limit: SessionTabs.maximumNameLength))
            }
            value.settings.name = name
            return replacing([value], stage: .edit)
        case let request as SetSpaceColor:
            try requireOwnedSpaces()
            var value = try space(request.spaceID)
            value.settings.storedColor = request.color
            return replacing([value], stage: .edit)
        case let request as SetBrowsingPreferences:
            try requireOwnedSpaces()
            var value = try space(request.spaceID)
            let previous = value.settings.browsingPreferences.dataRetention
            value.settings.browsingPreferences = BrowsingPreferences(
                contentBlocking: request.contentBlocking, dataRetention: request.dataRetention)
            if previous == request.dataRetention { return replacing([value], stage: .edit) }
            let swept = expired(value)
            return replacing([swept], stage: value == swept ? .edit : .expiry)
        case let request as ReorderSpaces:
            try requireOwnedSpaces()
            let byID = Dictionary(uniqueKeysWithValues: basis.spaces.map { ($0.id, $0) })
            guard request.spaceIDs.count == byID.count, Set(request.spaceIDs).count == byID.count,
                request.spaceIDs.allSatisfy({ byID[$0] != nil })
            else { throw Rejection.invalidSpaceOrder(InvalidSpaceOrder()) }
            var next = basis
            next.spaces = request.spaceIDs.map { byID[$0]! }
            return SessionMutation(session: next, stage: .edit)
        case let request as CreateSpace:
            try requireOwnedSpaces()
            guard !basis.spaces.contains(where: { $0.id == request.spaceID }) else {
                throw Rejection.spaceAlreadyExists(SpaceAlreadyExists(spaceID: request.spaceID))
            }
            guard basis.spaces.count < SessionValidation.maximumSpaces else {
                throw Rejection.spaceLimitReached(SpaceLimitReached(limit: SessionValidation.maximumSpaces))
            }
            var value = freshSpace(request.spaceID, number: basis.spaces.count + 1)
            let counts = Dictionary(grouping: basis.spaces.map { $0.settings.resolved.color }, by: { $0 }).mapValues(
                \.count)
            value.settings.storedColor = SpaceColor.all.min { counts[$0, default: 0] < counts[$1, default: 0] }!
            var next = basis
            next.spaces.append(value)
            var followUp = window(request.windowID)
            followUp.showSpace(value.id)
            followUp.showTab(value.tabs[0].id, in: value.id)
            return SessionMutation(session: next, stage: .creation, followUp: followUp)
        case let request as ResetPrivateBrowsing:
            guard kind.isPrivate else {
                throw Rejection.notPrivateWorkspace(NotPrivateWorkspace(workspaceID: workspaceID))
            }
            let value = freshSpace(ids(), number: 1)
            var next = basis
            next.spaces = [value]
            next.spaceDeletions = []
            var followUp = window(request.windowID)
            followUp.showSpace(value.id)
            followUp.showTab(value.tabs[0].id, in: value.id)
            return SessionMutation(session: next, stage: nil, followUp: followUp)
        case let request as BeginDeletingSpace:
            try requireOwnedSpaces()
            let (value, pending) = try deletion(request.spaceID)
            if let pending {
                guard pending.id == request.operationID else {
                    throw Rejection.wrongDeletionOperation(WrongDeletionOperation(spaceID: value.id))
                }
                return SessionMutation(session: basis, stage: .withdrawal)
            }
            try removable(basis.spaces.count - basis.spaceDeletions.count)
            var next = basis
            next.spaceDeletions.append(
                SpaceDeletionState(id: request.operationID, spaceID: value.id, profileID: value.profileID))
            var followUp = window(request.windowID)
            if followUp.window?.shownSpaceID == value.id {
                followUp.showSpace(
                    next.spaces.first { space in !next.spaceDeletions.contains { $0.spaceID == space.id } }!.id)
            }
            return SessionMutation(session: next, stage: .withdrawal, followUp: followUp)
        case let request as FinishDeletingSpace:
            try requireOwnedSpaces()
            let (value, pending) = try deletion(request.spaceID)
            guard let pending, pending.id == request.operationID else {
                throw Rejection.wrongDeletionOperation(WrongDeletionOperation(spaceID: value.id))
            }
            try removable(basis.spaces.count)
            let index = basis.spaces.firstIndex { $0.id == value.id }!
            var next = basis
            next.spaces.removeAll { $0.id == value.id }
            next.spaceDeletions.removeAll { $0 == pending }
            var followUp = window(request.windowID)
            if followUp.window?.shownSpaceID == value.id {
                followUp.showSpace(next.spaces[min(index, next.spaces.count - 1)].id)
            }
            return SessionMutation(session: next, stage: .removal, followUp: followUp)
        default: return nil
        }
    }
}
