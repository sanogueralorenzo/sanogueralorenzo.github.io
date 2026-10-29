import Foundation

extension SessionMutation {
    struct Sweep: Equatable {
        struct Retention: Equatable {
            let spaceID: UUID
            let records: DataRetentionPreferences
        }
        let at: Date
        let retention: [Retention]
        init(session: SessionState.Seed, at: Date) {
            self.at = at
            retention = session.spaces.map {
                Retention(spaceID: $0.id, records: $0.settings.browsingPreferences.dataRetention)
            }
        }
        func covers(_ session: SessionState.Seed, at now: Date) -> Bool {
            let elapsed = now.timeIntervalSince(at)
            return elapsed >= 0 && elapsed < 60 && retention == Self(session: session, at: now).retention
        }
    }
}

extension SessionMutations {
    func expired(_ source: SpaceState.Seed) -> SpaceState.Seed {
        var value = source
        let retention = value.settings.browsingPreferences.dataRetention
        if let lifetime = retention.history.lifetime {
            value.history.removeAll { now.timeIntervalSince($0.lastVisitedAt) > lifetime }
        }
        if let lifetime = retention.archive.lifetime {
            value.archivedTabs.removeAll { now.timeIntervalSince($0.archivedAt) > lifetime }
        }
        return value
    }
    var editableSpaces: [SpaceState.Seed] {
        basis.spaces.filter { space in !basis.spaceDeletions.contains { $0.spaceID == space.id } }
    }
    func recordEdit(_ request: some SessionIntent) throws -> SessionMutation? {
        switch request {
        case let request as ClearHistory:
            let spaces = try request.spaceID.map { [try space($0)] } ?? editableSpaces
            let duration: TimeInterval?
            switch request.range {
            case .lastHour: duration = 3600
            case .lastDay: duration = 86400
            case .lastWeek: duration = 7 * 86400
            case .lastFourWeeks: duration = 28 * 86400
            default: duration = nil
            }
            let cleared = spaces.map { source in
                var value = source
                value.history.removeAll { entry in
                    duration.map { entry.lastVisitedAt >= now.addingTimeInterval(-$0) } ?? true
                }
                return value
            }
            return replacing(cleared, stage: .deletion)
        case let request as RemoveHistoryAddress:
            var value = try space(request.spaceID)
            if let normalized = BrowserWebAddress.normalized(request.address) {
                value.history.removeAll { Data($0.url.utf8) == Data(normalized.utf8) }
            }
            return replacing([value], stage: .deletion)
        case let request as ReopenClosedTab:
            let original = try space(request.spaceID)
            guard
                let newest = original.archivedTabs.reduce(
                    nil as ArchivedTabState.Seed?,
                    { best, next in best.map { $0.archivedAt >= next.archivedAt ? $0 : next } ?? next })
            else {
                throw Rejection.noArchivedTabs(NoArchivedTabs(spaceID: original.id))
            }
            return try recordEdit(
                RestoreArchivedTab(
                    workspaceID: workspaceID, windowID: request.windowID, spaceID: original.id, tabID: newest.tab.id))
        case let request as RestoreArchivedTab:
            var original = try space(request.spaceID)
            guard let index = original.archivedTabs.firstIndex(where: { $0.tab.id == request.tabID }) else {
                throw Rejection.unknownArchivedTab(UnknownArchivedTab(tabID: request.tabID))
            }
            guard !basis.spaces.contains(where: { $0.tabs.contains { $0.id == request.tabID } }) else {
                throw Rejection.tabAlreadyExists(TabAlreadyExists(tabID: request.tabID))
            }
            let archived = original.archivedTabs.remove(at: index)
            var values = try SessionTabs(original)
            let restored = try values.restore(archived.tab, at: now)
            var followUp = window(request.windowID)
            followUp.showTab(restored.id, in: original.id)
            return replacing([values.capture(original)], stage: .creation, followUp: followUp)
        case is SweepExpiredRecords:
            if lastSweep?.covers(basis, at: now) == true { return nil }
            var mutation = replacing(editableSpaces.map(expired), stage: .expiry)
            mutation.sweep = SessionMutation.Sweep(session: basis, at: now)
            return mutation
        default: return nil
        }
    }
}
