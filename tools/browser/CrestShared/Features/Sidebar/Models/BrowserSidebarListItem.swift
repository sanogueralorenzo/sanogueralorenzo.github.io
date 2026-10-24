import Foundation

/// One row a sidebar list draws, with the objects its row view stands for:
/// a tab, a folder, or a split's members in order. Items are equal when they
/// hand their row the same objects and values, as SwiftUI compares a view's
/// inputs, so a list that redraws leaves every unchanged row alone.
struct BrowserSidebarListItem: Identifiable, Equatable {
    // MARK: - Types

    enum Content: Equatable {
        case tab(TabStateModel)
        case folder(FolderStateModel)
        case split(UUID, members: [TabStateModel])

        // MARK: - Actions - Tabs

        /// Whether the row stands for the tab `tabID` of `space`: is it, is
        /// the split around it, or is a folder that holds it, however deep.
        @MainActor
        func contains(tabID: UUID, in space: SpaceModel) -> Bool {
            switch self {
            case .tab(let tab): tab.id == tabID
            case .split(_, let members): members.contains { $0.id == tabID }
            case .folder(let folder): space.tabIDs(inFolder: folder.id).contains(tabID)
            }
        }

        // MARK: - Actions - Equality

        static func == (lhs: Content, rhs: Content) -> Bool {
            switch (lhs, rhs) {
            case (.tab(let tab), .tab(let other)): tab === other
            case (.folder(let folder), .folder(let other)): folder === other
            case (.split(let group, let members), .split(let otherGroup, let others)):
                group == otherGroup && members.elementsEqual(others, by: ===)
            default: false
            }
        }
    }

    // MARK: - Variables

    /// The row's identity, by kind, which `ForEach` and the reorder registry
    /// key on. A split's identity is its group, never a member's.
    let id: BrowserSidebarReorderItemID
    let content: Content
    /// How many folders hold the row.
    let depth: Int
    /// The first tab of the row after this one in its list, which a shell that
    /// draws insertion lines on the rows aims a drop below this row at.
    let followingTabID: UUID?

    /// The identity collection motion animates this row's arrival and
    /// departure under, spelled as the sidebar always spelled it.
    var collectionMotionID: String { id.collectionMotionID }

    /// The first tab the row stands for, or nil for a folder.
    var firstTabID: UUID? {
        switch content {
        case .tab(let tab): tab.id
        case .split(_, let members): members.first?.id
        case .folder: nil
        }
    }

    // MARK: - Actions - Reading

    /// The rows `list` shows, with the objects each stands for. A row whose
    /// object the read model does not hold yet is left out until it does.
    /// Only a shell that draws insertion lines on the rows learns which tab
    /// follows each row, so elsewhere a move hands no row new inputs.
    /// Reading it observes the list and each looked-up record's membership.
    @MainActor
    static func items(
        of list: SidebarListModel, in space: SpaceModel, namesFollowingTabs: Bool = false
    ) -> [BrowserSidebarListItem] {
        var items: [BrowserSidebarListItem] = []
        for row in list.rows {
            let content: Content?
            if row.kind.opensList {
                content = space.folders.model(row.id).map(Content.folder)
            } else if row.kind.groupsTabs {
                let members = row.members.compactMap { space.tabs.model($0) }
                content = members.isEmpty ? nil : .split(row.id, members: members)
            } else {
                content = space.tabs.model(row.id).map(Content.tab)
            }
            guard let content else { continue }
            items.append(
                BrowserSidebarListItem(
                    id: BrowserSidebarReorderItemID(row), content: content, depth: row.depth, followingTabID: nil))
        }
        guard namesFollowingTabs else { return items }
        var following: UUID?
        for index in items.indices.reversed() {
            let item = items[index]
            items[index] = BrowserSidebarListItem(
                id: item.id, content: item.content, depth: item.depth, followingTabID: following)
            if let first = item.firstTabID { following = first }
        }
        return items
    }
}

extension BrowserSidebarReorderItemID {
    /// The identity of the row the core's outline lists.
    init(_ row: SidebarRow) {
        if row.kind.opensList {
            self = .folder(row.id)
        } else if row.kind.groupsTabs {
            self = .splitGroup(row.id)
        } else {
            self = .tab(row.id)
        }
    }

    /// The identity collection motion keys the row under.
    var collectionMotionID: String {
        switch self {
        case .tab(let id): "tab-\(id.uuidString)"
        case .splitGroup(let id): "split-\(id.uuidString)"
        case .folder(let id): "folder-\(id.uuidString)"
        }
    }
}
