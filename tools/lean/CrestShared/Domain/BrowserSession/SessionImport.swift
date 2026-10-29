import Foundation

/// One detached import. Origins travel alongside values through edits and identity repair.
struct SessionImport {
    private struct Origin: Hashable {
        let source: Int?
        let tab: UUID
    }
    private final class Draft {
        var state: SpaceState.Seed
        let original: SpaceState.Seed?
        var origins: [Origin]
        let archiveOrigins: [Origin]
        var shown: UUID?
        init(_ state: SpaceState.Seed, source: Int?) {
            self.state = state
            original = source == nil ? state : nil
            origins = state.tabs.map { Origin(source: source, tab: $0.id) }
            archiveOrigins = state.archivedTabs.map { Origin(source: source, tab: $0.tab.id) }
        }
    }
    private let basis: SessionState.Seed
    private var spaces: [Draft]
    private let inputs: [Draft]
    private var reviewed: Set<Origin> = []
    private var marker: UUID?
    private var affected: Draft?

    init(_ basis: SessionState.Seed, inputs: [SpaceState.Seed]) throws {
        self.basis = basis
        spaces = basis.spaces.map { Draft($0, source: nil) }
        self.inputs = inputs.enumerated().map { Draft($0.element, source: $0.offset) }
        marker = basis.disposableSeedMarker
        for input in inputs
        where SessionTabs.repairedSplits(input.tabs).map(\.splitGroupID) != input.tabs.map(\.splitGroupID) {
            throw Rejection.invalidImport(InvalidImport(flaw: .malformedSplit))
        }
    }
    private func capacity(_ existing: Int, adding: Int) throws {
        guard existing <= SessionValidation.maximumSpaces - adding else {
            throw Rejection.spaceLimitReached(SpaceLimitReached(limit: SessionValidation.maximumSpaces))
        }
    }
    private mutating func replaceSeed() throws {
        if let deletion = basis.spaceDeletions.first {
            throw Rejection.spaceBeingDeleted(SpaceBeingDeleted(spaceID: deletion.spaceID))
        }
        spaces.removeAll()
    }
    mutating func add() throws {
        let replace = marker != nil && spaces.count + inputs.count > SessionValidation.maximumSpaces
        try capacity(replace ? 0 : spaces.count, adding: inputs.count)
        if replace {
            try replaceSeed()
            marker = nil
        }
        for input in inputs {
            input.shown = input.state.tabs.first?.id
            spaces.append(input)
        }
        affected = inputs.first
    }
    mutating func review(_ choices: [ReviewedImportSpace.Seed], ids: () -> UUID) throws {
        let inputIDs = inputs.map { $0.state.id }
        let choiceIDs = choices.map { $0.source.id }
        guard Set(inputIDs).count == inputIDs.count, Set(choiceIDs).count == choiceIDs.count,
            Set(inputIDs) == Set(choiceIDs)
        else {
            throw Rejection.invalidImport(InvalidImport(flaw: .unpairedChoices))
        }
        let included = choices.filter(\.included)
        guard !included.isEmpty else { throw Rejection.noIncludedSpaces(NoIncludedSpaces()) }
        try capacity(marker != nil ? 0 : spaces.count, adding: included.filter { $0.destinationID == nil }.count)
        if marker != nil { try replaceSeed() }
        for choice in included {
            let input = inputs.first { $0.state.id == choice.source.id }!
            guard let destination = choice.destinationID.map({ id in spaces.first { $0.state.id == id } }) ?? input
            else { continue }
            if basis.spaceDeletions.contains(where: { $0.spaceID == destination.state.id }) {
                throw Rejection.spaceBeingDeleted(SpaceBeingDeleted(spaceID: destination.state.id))
            }
            let name = BrowserAddress.trimmed(choice.customization.name)
            destination.state.settings.name = name.isEmpty ? "Untitled Space" : name
            try merge(choice, input: input, destination: destination, ids: ids)
            if choice.destinationID == nil { spaces.append(destination) }
            if affected == nil { affected = destination }
        }
        if affected != nil { marker = nil }
    }
    private static func folderKey(_ title: String) -> String {
        String(
            String.UnicodeScalarView(
                title.decomposedStringWithCompatibilityMapping.unicodeScalars.filter {
                    // .NET Char.IsLetterOrDigit reads UTF-16 characters; supplementary scalars are surrogate pairs.
                    $0.value <= 0xFFFF
                        && ([
                            .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                            .decimalNumber,
                        ].contains($0.properties.generalCategory))
                })
        ).lowercased()
    }
    private mutating func merge(_ choice: ReviewedImportSpace.Seed, input: Draft, destination: Draft, ids: () -> UUID)
        throws
    {
        let isNew = choice.destinationID == nil
        let included = Set(choice.includedTabIDs)
        let overrides = choice.placements.reduce(into: [UUID: TabPlacement]()) { $0[$1.tabID] = $1.placement }
        func placement(_ tab: TabState.Seed) -> TabPlacement { overrides[tab.id] ?? tab.placement }
        var additions = input.state.tabs.indices.filter { included.contains(input.state.tabs[$0].id) }
        let room = max(0, SessionTabs.maximumTabs - (isNew ? 0 : destination.state.tabs.count))
        if additions.count > room {
            let preferred = Set(
                additions.sorted { a, b in
                    let left = placement(input.state.tabs[a]) == .saved ? 1 : 0
                    let right = placement(input.state.tabs[b]) == .saved ? 1 : 0
                    return left == right ? a < b : left < right
                }.prefix(room))
            additions = additions.filter(preferred.contains)
        }
        let sourceFolders = input.state.folders
        let byID = sourceFolders.reduce(into: [UUID: FolderState.Seed]()) { if $0[$1.id] == nil { $0[$1.id] = $1 } }
        func kept(_ tab: TabState.Seed) -> Bool {
            tab.folderID.flatMap { byID[$0] }.map { $0.location == placement(tab) && $0.location.holdsFolders } ?? false
        }
        var required = Set(additions.compactMap { kept(input.state.tabs[$0]) ? input.state.tabs[$0].folderID : nil })
        var pending = Array(required)
        while let id = pending.popLast() {
            if let parent = byID[id]?.parentID, required.insert(parent).inserted { pending.append(parent) }
        }
        var folders = isNew ? [] : destination.state.folders
        var mapping: [UUID: UUID] = [:]
        for folder in try SessionFolders.repairedPreorder(sourceFolders) where required.contains(folder.id) {
            let original = byID[folder.id]!
            let parent = folder.parentID.flatMap { mapping[$0] }
            if let match = folders.first(where: {
                $0.parentID == parent && $0.location == original.location
                    && Self.folderKey($0.title) == Self.folderKey(original.title)
            }) {
                mapping[folder.id] = match.id
                continue
            }
            guard folders.count < SessionFolders.maximumCount else { continue }
            var value = original
            while folders.contains(where: { $0.id == value.id }) { value.id = ids() }
            value.parentID = parent
            value.isCollapsed = false
            value.collapseModifiedAt = nil
            value.orderAnchorTabID = nil
            folders.append(value)
            mapping[folder.id] = value.id
        }
        let existing = isNew ? [] : destination.state.tabs
        var counts = Dictionary(grouping: existing, by: \.placement).mapValues(\.count)
        var overflow = folders.first { $0.title.lowercased() == "imported pinned tabs" }
        var edited: [TabState.Seed] = []
        let origins = additions.map { input.origins[$0] }
        for index in additions {
            var tab = input.state.tabs[index]
            var location = placement(tab)
            counts[location, default: 0] += 1
            if let capacity = location.capacity, counts[location]! > capacity {
                location = .saved
                if overflow == nil && folders.count < SessionFolders.maximumCount {
                    overflow = FolderState.Seed(id: ids(), title: "Imported Pinned Tabs")
                    folders.append(overflow!)
                }
                tab.folderID = overflow?.id
            } else {
                tab.folderID = kept(tab) ? tab.folderID.flatMap { mapping[$0] } : nil
            }
            tab.placement = location
            tab.savedURL = location.isDurable ? tab.savedURL ?? tab.url : nil
            tab.symbol = location.importedSymbol ?? tab.symbol
            edited.append(tab)
        }
        var mapped: [UUID: UUID] = [:]
        let held = Set(existing.compactMap(\.splitGroupID))
        for index in edited.indices {
            if let group = edited[index].splitGroupID {
                if mapped[group] == nil {
                    var id = group
                    while held.contains(id) || mapped.values.contains(id) { id = ids() }
                    mapped[group] = id
                }
                edited[index].splitGroupID = mapped[group]
            }
        }
        let repaired = Array(SessionTabs.repairedSplits(existing + edited).dropFirst(existing.count))
        let memberships = Dictionary(grouping: repaired.compactMap(\.splitGroupID), by: { $0 }).mapValues(\.count)
        for index in edited.indices {
            let group = repaired[index].splitGroupID
            edited[index].splitGroupID =
                group == edited[index].splitGroupID && group.map { memberships[$0, default: 0] >= 2 } == true
                ? group : nil
        }
        reviewed.formUnion(origins)
        destination.state.folders = folders
        destination.state.tabs = existing + edited
        destination.origins = (isNew ? [] : destination.origins) + origins
        if isNew { destination.shown = edited.first?.id }
    }
    private func reserve(
        _ draft: Draft, folders heldFolders: inout Set<UUID>, history heldHistory: inout Set<UUID>, ids: () -> UUID
    ) {
        let originalFolders = Set(draft.original?.folders.map(\.id) ?? [])
        let originalHistory = Set(draft.original?.history.map(\.id) ?? [])
        var mapping: [UUID: UUID] = [:]
        for index in draft.state.folders.indices {
            let old = draft.state.folders[index].id
            var id = old
            if !originalFolders.contains(old) { while !heldFolders.insert(id).inserted { id = ids() } }
            if mapping[old] == nil { mapping[old] = id }
            draft.state.folders[index].id = id
        }
        for index in draft.state.folders.indices {
            if let parent = draft.state.folders[index].parentID {
                draft.state.folders[index].parentID = mapping[parent] ?? parent
            }
        }
        for index in draft.state.tabs.indices {
            if let folder = draft.state.tabs[index].folderID {
                draft.state.tabs[index].folderID = mapping[folder] ?? folder
            }
        }
        draft.state.history = draft.state.history.map { value in
            var id = value.id
            if !originalHistory.contains(id) { while !heldHistory.insert(id).inserted { id = ids() } }
            return HistoryEntryState(
                id: id, url: value.url, title: value.title, firstVisitedAt: value.firstVisitedAt,
                lastVisitedAt: value.lastVisitedAt, visitCount: value.visitCount)
        }
    }
    mutating func finish(workspaceID: UUID, now: Date, ids: @escaping () -> UUID, followUp: inout SessionWindowFollowUp)
        throws -> SessionMutation
    {
        var folders = Set(basis.spaces.flatMap { $0.folders.map(\.id) })
        var history = Set(basis.spaces.flatMap { $0.history.map(\.id) })
        for draft in spaces {
            reserve(draft, folders: &folders, history: &history, ids: ids)
            for index in draft.state.tabs.indices
            where reviewed.contains(draft.origins[index]) && !draft.state.tabs[index].placement.isDurable
                && draft.state.tabs[index].lastActivatedAt < now
            { draft.state.tabs[index].lastActivatedAt = now }
        }
        let affectedIndex = affected.flatMap { affected in spaces.firstIndex { $0 === affected } }
        let shown = spaces.enumerated().compactMap { si, draft in
            draft.shown.flatMap { id in draft.state.tabs.firstIndex { $0.id == id }.map { (si, $0) } }
        }
        var next = basis
        next.spaces = spaces.map(\.state)
        next.disposableSeedMarker = marker
        var repair = SessionRepair(now: now, ids: ids)
        next = try repair.repair(next).session
        if let affectedIndex { followUp.showSpace(next.spaces[affectedIndex].id) }
        for (si, ti) in shown { followUp.showTab(next.spaces[si].tabs[ti].id, in: next.spaces[si].id) }
        var imported: [ImportedTab] = []
        var effects: [any CoreChange] = []
        func place(_ origin: Origin, id: UUID) {
            if let source = origin.source {
                imported.append(ImportedTab(tabID: id, source: source, sourceTabID: origin.tab))
            } else if origin.tab != id {
                effects.append(TabCopied(workspaceID: workspaceID, sourceTabID: origin.tab, copyTabID: id))
            }
        }
        for (si, draft) in spaces.enumerated()
        where !basis.spaceDeletions.contains(where: { $0.spaceID == draft.state.id }) {
            for ti in draft.state.tabs.indices { place(draft.origins[ti], id: next.spaces[si].tabs[ti].id) }
            let archiveOrigins = draft.state.archivedTabs.indices.filter {
                !SessionTabs.isStartPage(draft.state.archivedTabs[$0].tab)
            }.map { draft.archiveOrigins[$0] }
            for (ti, origin) in archiveOrigins.enumerated() {
                place(origin, id: next.spaces[si].archivedTabs[ti].tab.id)
            }
        }
        if !imported.isEmpty { effects.append(TabsImported(workspaceID: workspaceID, tabs: imported)) }
        return SessionMutation(session: next, stage: .importing, followUp: followUp, effects: effects)
    }
}

extension SessionMutations {
    func importing(_ request: ImportSpaces) throws -> SessionMutation {
        try requirePreferences()
        var values = try SessionImport(basis, inputs: request.spaces)
        try values.add()
        var followUp = window(request.windowID)
        return try values.finish(workspaceID: workspaceID, now: now, ids: ids, followUp: &followUp)
    }
    func importing(_ request: ImportReviewedSpaces) throws -> SessionMutation {
        try requirePreferences()
        var values = try SessionImport(basis, inputs: request.reviews.map(\.source))
        try values.review(request.reviews, ids: ids)
        var followUp = window(request.windowID)
        return try values.finish(workspaceID: workspaceID, now: now, ids: ids, followUp: &followUp)
    }
}
