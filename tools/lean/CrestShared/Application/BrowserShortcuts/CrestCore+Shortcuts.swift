import Foundation

extension CrestCore {
    /// Numbered shortcuts follow sidebar stops, treating a split as one stop
    /// and omitting collapsed folder contents and Spaces being deleted.
    func numberedSelections(windowID: UUID) -> [ShortcutCommand: NumberedSelection] {
        drain()
        guard let window = state.windows[windowID], let workspace = state.workspaces[window.workspaceID] else {
            return [:]
        }
        let deleting = Set(workspace.spaceDeletions.map(\.spaceID))
        let spaces = workspace.spaces.models.filter { !deleting.contains($0.id) }
        let tabs = spaces.first { $0.id == window.shownSpaceID }?.shortcutStops ?? []
        var selections: [ShortcutCommand: NumberedSelection] = [:]
        for command in ShortcutCommand.all {
            guard let target = command.selects, let number = command.number, number > 0 else { continue }
            let index = number - 1
            switch target {
            case .tab:
                guard tabs.indices.contains(index) else { continue }
                selections[command] = NumberedSelection(
                    command: command, target: target, spaceID: window.shownSpaceID, tabID: tabs[index])
            case .space:
                guard spaces.indices.contains(index) else { continue }
                selections[command] = NumberedSelection(
                    command: command, target: target, spaceID: spaces[index].id, tabID: nil)
            }
        }
        return selections
    }
}

extension SpaceModel {
    var shortcutStops: [UUID] {
        var stops: [UUID] = []
        func walk(_ rows: [SidebarRow]) {
            for row in rows {
                if row.kind.opensList {
                    if folders.model(row.id)?.isCollapsed != true { walk(sidebar.inside(row.id).rows) }
                } else if let first = row.members.first {
                    stops.append(first)
                }
            }
        }
        for placement in TabPlacement.all { walk(sidebar.section(placement).rows) }
        return stops
    }

    /// The first free tab after the shown row in the same sidebar list.
    /// Joining it still goes through the session's split validation.
    func hasShortcutSplitCandidate(after tabID: UUID?) -> Bool {
        guard let tabID else { return false }
        for list in sidebar.lists {
            let rows = list.rows
            guard let index = rows.firstIndex(where: { !$0.kind.opensList && $0.members.contains(tabID) }) else {
                continue
            }
            return rows.dropFirst(index + 1).contains { row in
                row.kind == .tab && tabs.model(row.id)?.splitGroupID == nil
            }
        }
        return false
    }
}
