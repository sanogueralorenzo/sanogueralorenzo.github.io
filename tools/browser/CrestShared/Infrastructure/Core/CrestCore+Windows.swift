import Foundation

extension CrestCore {
    /// The tab a Space shows when no window chose one, by the core's rule: the
    /// first open tab, else the first pinned one, else the first tab. For a
    /// Space no window shows, such as a draft, a preview or an import under
    /// review.
    @MainActor
    func fallbackTabID(in space: SpaceModel) -> UUID? {
        let tabs = space.tabs.models
        guard let index = (try? query(FallbackTab(placements: tabs.map(\.placement))))?.index,
            tabs.indices.contains(index)
        else { return nil }
        return tabs[index].id
    }
}
