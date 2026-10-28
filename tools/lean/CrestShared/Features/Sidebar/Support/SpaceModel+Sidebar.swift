import Foundation

/// What the sidebar reads out of a Space's outline beyond one list: a split's
/// members, the row a tab shows in, and the folders a menu offers. Each walk
/// observes the lists it reads.
extension SpaceModel {
    // MARK: - Types

    /// A folder a menu offers, with the folders around it named in its title.
    struct FolderChoice: Identifiable {
        let folder: FolderStateModel
        let pathTitle: String

        var id: UUID { folder.id }
    }

    // MARK: - Actions - Reading

    /// The members of the split the sidebar shows as one row, in order, or
    /// none when it shows no such row.
    func splitMembers(of groupID: UUID) -> [TabStateModel] {
        for list in sidebar.lists {
            if let row = list.rows.first(where: { $0.id == groupID && $0.kind.groupsTabs }) {
                return row.members.compactMap { tabs.model($0) }
            }
        }
        return []
    }

    /// The split the sidebar shows the tab in as one row, or nil when it shows
    /// the tab alone.
    func shownSplit(containing tabID: UUID) -> UUID? {
        guard let groupID = tabs.model(tabID)?.splitGroupID else { return nil }
        return splitMembers(of: groupID).contains { $0.id == tabID } ? groupID : nil
    }

    /// The folders of `sections`, in the order the sidebar lists them, each
    /// titled with the path of folders that holds it.
    func folderChoices(in sections: [TabPlacement]) -> [FolderChoice] {
        var choices: [FolderChoice] = []
        func walk(_ list: SidebarListModel, path: String?) {
            for row in list.rows where row.kind.opensList {
                guard let folder = folders.model(row.id) else { continue }
                let title = path.map { "\($0) › \(folder.title)" } ?? folder.title
                choices.append(FolderChoice(folder: folder, pathTitle: title))
                walk(sidebar.inside(folder.id), path: title)
            }
        }
        for section in sections { walk(sidebar.section(section), path: nil) }
        return choices
    }

    /// The folders inside the folder, however deep, in the order the sidebar
    /// lists them.
    func folderChoices(inside folderID: UUID) -> [FolderChoice] {
        var choices: [FolderChoice] = []
        var visited: Set<UUID> = [folderID]
        func walk(_ list: SidebarListModel, path: String) {
            for row in list.rows where row.kind.opensList && visited.insert(row.id).inserted {
                guard let folder = folders.model(row.id) else { continue }
                let title = "\(path) › \(folder.title)"
                choices.append(FolderChoice(folder: folder, pathTitle: title))
                walk(sidebar.inside(folder.id), path: title)
            }
        }
        walk(sidebar.inside(folderID), path: folders.model(folderID)?.title ?? "")
        return choices
    }

    /// Every tab the folder holds, however deep, in the order the sidebar
    /// lists them.
    func tabIDs(inFolder folderID: UUID) -> [UUID] {
        var result: [UUID] = []
        var visited: Set<UUID> = []
        func walk(_ folderID: UUID) {
            guard visited.insert(folderID).inserted else { return }
            for row in sidebar.inside(folderID).rows {
                if row.kind.opensList { walk(row.id) } else { result.append(contentsOf: row.members) }
            }
        }
        walk(folderID)
        return result
    }
}
