import Foundation

/// What a Space's sidebar lists, in the pieces the core publishes: the top
/// level of each section and the inside of each folder, each a list observed
/// on its own. Looking a list up observes nothing, so a view that reads one
/// list redraws only when that list changes. Which folders are collapsed,
/// and whether the saved section is, the folders and settings say; every
/// list holds its rows either way.
@MainActor
final class SidebarModel {
    // MARK: - Variables

    /// Each section's top level, by the section's tag.
    private let sections: [SidebarListModel]
    /// Each folder's inside. A folder's list is made the first time it is
    /// read or published, so a view may read it before its rows arrive.
    private var insides: [UUID: SidebarListModel] = [:]

    // MARK: - Initializers

    init(_ outline: SidebarOutline) {
        sections = TabPlacement.all.map { _ in SidebarListModel() }
        replace(with: outline)
    }

    // MARK: - Actions - Reading

    /// The top level of `placement`'s section.
    func section(_ placement: TabPlacement) -> SidebarListModel {
        sections[placement.tag]
    }

    /// The inside of the folder, empty until the core lists a row in it.
    func inside(_ folderID: UUID) -> SidebarListModel {
        if let list = insides[folderID] { return list }
        let list = SidebarListModel()
        insides[folderID] = list
        return list
    }

    /// Every list the model holds: the sections' top levels, then the folder
    /// insides it has made, in no particular order. Reading it observes
    /// nothing; reading a list's rows observes that list.
    var lists: [SidebarListModel] {
        sections + Array(insides.values)
    }

    /// The outline the lists hold, with the insides of `folders` in their
    /// order. Reading it observes every list it names.
    func outline(folders: [FolderStateModel]) -> SidebarOutline {
        SidebarOutline(
            lists: TabPlacement.all.map { SidebarList(section: $0, folderID: nil, rows: section($0).rows) }
                + folders.map { SidebarList(section: $0.location, folderID: $0.id, rows: inside($0.id).rows) })
    }

    // MARK: - Actions - Changes

    /// Each list the change names takes its rows, and the lists of the
    /// removed folders are gone.
    func apply(_ change: SidebarChanged) {
        for folderID in change.removedFolderIDs { insides[folderID] = nil }
        for list in change.lists { model(of: list).update(list.rows) }
    }

    /// The Space arrived whole: every list takes the outline's rows, and the
    /// lists of folders the outline lacks are gone.
    func replace(with outline: SidebarOutline) {
        let folders = Set(outline.lists.compactMap(\.folderID))
        insides = insides.filter { folders.contains($0.key) }
        for list in outline.lists { model(of: list).update(list.rows) }
    }

    private func model(of list: SidebarList) -> SidebarListModel {
        list.folderID.map(inside) ?? section(list.section)
    }
}
