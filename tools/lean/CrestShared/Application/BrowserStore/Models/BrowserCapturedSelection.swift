import Foundation

/// A window's multi-selection as the core previewed it when a menu opened or
/// a drag began: the Space it was made in, and what its picks hold there, in
/// sidebar order, with the `TabSelection` the batch intents and drops take.
/// Views read it to label and lift the selection; the core decides every
/// action on it.
struct BrowserCapturedSelection: Equatable, Sendable {
    // MARK: - Variables

    let assignment: BrowserSpaceRuntimeAssignment
    let selected: SelectedTabs

    /// The selection as the actions take it.
    var selection: TabSelection { selected.selection }

    /// Every tab the selection holds, in sidebar order.
    var ids: [UUID] { selected.members.map(\.id) }

    /// The tabs the selection holds, with where each stands.
    var members: [SelectedTab] { selected.members }

    /// What the person picked that no picked folder holds, in sidebar order.
    var rootItems: [BrowserSelectionItemID] {
        selected.roots.map { $0.kind.opensList ? .folder($0.id) : .tab($0.id) }
    }

    /// The picked folders and every folder inside them.
    var folderIDs: Set<UUID> { Set(selected.folderIDs) }

    var hasFolders: Bool { !selected.folderIDs.isEmpty }

    var spaceID: UUID { assignment.spaceID }
}
