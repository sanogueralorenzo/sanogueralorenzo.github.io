import Foundation

/// Value rules for the session's folder forest. Sidebar order stays in the stored array.
struct SessionFolders {
    enum InvalidTree: Error { case invalid }
    static let maximumCount = 500
    let values: [FolderState.Seed]
    private let byID: [UUID: FolderState.Seed]

    init(_ values: [FolderState.Seed]) {
        self.values = values
        byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    func folder(_ id: UUID) throws -> FolderState.Seed {
        guard let value = byID[id] else { throw Rejection.unknownFolder(UnknownFolder(folderID: id)) }
        return value
    }
    func children(_ parent: UUID?) -> [FolderState.Seed] { values.filter { $0.parentID == parent } }
    func depth(_ id: UUID) throws -> Int {
        var value = try folder(id)
        var seen: Set<UUID> = [id]
        var depth = 0
        while let parent = value.parentID {
            depth += 1
            guard seen.insert(parent).inserted, depth < FolderState.maximumDepth, let held = byID[parent] else {
                throw InvalidTree.invalid
            }
            value = held
        }
        return depth
    }
    func validate() throws {
        guard values.count <= Self.maximumCount, byID.count == values.count else { throw InvalidTree.invalid }
        for value in values {
            guard value.location.holdsFolders,
                value.parentID == nil || byID[value.parentID!]?.location == value.location
            else { throw InvalidTree.invalid }
            _ = try depth(value.id)
        }
    }
    func displayOrder() throws -> [FolderState.Seed] {
        try validate()
        var result: [FolderState.Seed] = []
        func append(_ parent: UUID?) {
            for value in children(parent) {
                result.append(value)
                append(value.id)
            }
        }
        append(nil)
        return result
    }
    func subtree(_ id: UUID) throws -> Set<UUID> {
        _ = try folder(id)
        var result: Set<UUID> = []
        var pending = [id]
        while let next = pending.popLast() {
            if result.insert(next).inserted { pending.append(contentsOf: children(next).map(\.id)) }
        }
        return result
    }
    func pathTitle(_ id: UUID) throws -> String {
        var value = try folder(id)
        var titles = [value.title]
        var seen: Set<UUID> = [id]
        while let parent = value.parentID, seen.insert(parent).inserted {
            value = try folder(parent)
            titles.append(value.title)
        }
        return titles.reversed().joined(separator: " › ")
    }
    func tabAnchor(_ id: UUID, tabs: [TabState.Seed]) throws -> UUID? {
        let held = try subtree(id)
        if let tab = tabs.first(where: { $0.folderID.map(held.contains) == true }) { return tab.id }
        let anchor = try folder(id).orderAnchorTabID
        return tabs.contains { $0.id == anchor } ? anchor : nil
    }
    func preservingOrder(removing: Set<UUID>, tabs: [TabState.Seed], excluding: Set<UUID> = []) throws -> [FolderState
        .Seed]
    {
        try values.map { source in
            guard !excluding.contains(source.id) else { return source }
            let held = try subtree(source.id)
            let members = tabs.filter { $0.folderID.map(held.contains) == true }
            guard !members.contains(where: { !removing.contains($0.id) }),
                let old = members.first?.id ?? source.orderAnchorTabID, removing.contains(old),
                let start = tabs.firstIndex(where: { $0.id == old })
            else { return source }
            let parent = try source.parentID.map(subtree)
            var value = source
            value.orderAnchorTabID =
                tabs[start...].first {
                    !removing.contains($0.id) && $0.placement == source.location
                        && (parent == nil || $0.folderID.map { parent!.contains($0) } == true)
                }?.id
            return value
        }
    }
    func emptyPredecessors(before: UUID?, anchor: UUID?, parent: UUID?, placement: TabPlacement, tabs: [TabState.Seed])
        throws -> Set<UUID>
    {
        let target = try before.map(subtree) ?? []
        let targetEmpty = !tabs.contains { $0.folderID.map(target.contains) == true }
        var result: Set<UUID> = []
        for value in children(parent) where value.location == placement {
            if value.id == before && targetEmpty { break }
            let held = try subtree(value.id)
            if !tabs.contains(where: { $0.folderID.map(held.contains) == true }),
                try tabAnchor(value.id, tabs: tabs) == anchor
            {
                result.insert(value.id)
            }
        }
        return result
    }
    static func repairedPreorder(_ source: [FolderState.Seed]) throws -> [FolderState.Seed] {
        var accepted: [FolderState.Seed] = []
        var parents: [UUID: (depth: Int, location: TabPlacement)] = [:]
        for source in source {
            if accepted.count == maximumCount { break }
            if parents[source.id] != nil { continue }
            var value = source
            if let parent = value.parentID,
                parent == value.id || parents[parent] == nil || parents[parent]!.depth + 1 >= FolderState.maximumDepth
            {
                value.parentID = nil
            }
            if let parent = value.parentID { value.location = parents[parent]!.location }
            guard value.location.holdsFolders else { continue }
            accepted.append(value)
            parents[value.id] = (value.parentID.map { parents[$0]!.depth + 1 } ?? 0, value.location)
        }
        return try SessionFolders(accepted).displayOrder()
    }
}
