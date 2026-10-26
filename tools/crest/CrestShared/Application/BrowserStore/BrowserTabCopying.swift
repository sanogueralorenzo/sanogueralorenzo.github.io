import Foundation

/// The window's page owner can give a copy the engine state its source's page
/// keeps before the copy's page mounts. No engine object is shared.
@MainActor
protocol BrowserTabCopying: AnyObject {
    /// Gives the copy `copyID` of `source`, a tab of the Space `space` names,
    /// the engine state its first page starts from.
    func prepareTabCopy(from source: TabState, copyID: UUID, in space: BrowserSpaceRuntimeAssignment)
}

/// The tabs of a Space as they were before an intent that copies some of
/// them, which the copies' pages start from.
struct BrowserTabCopySources {
    // MARK: - Variables

    let space: BrowserSpaceRuntimeAssignment
    let tabs: [UUID: TabState]

    // MARK: - Initializers

    /// The tabs `space` holds in the read model now.
    @MainActor
    init(_ space: SpaceModel) {
        self.space = BrowserSpaceRuntimeAssignment(space: space)
        tabs = Dictionary(uniqueKeysWithValues: space.tabs.models.map { ($0.id, $0.value) })
    }
}
