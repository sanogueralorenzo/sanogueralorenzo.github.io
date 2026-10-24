using CrestCore.Application;

namespace CrestCore.Contracts;

/// Which tab a Space shows when no window chose one, for a draft Space the
/// session does not hold yet, given its tabs' placements in Space order: the
/// first open tab, else the first pinned one, else the first tab.
public sealed record FallbackTab(IReadOnlyList<TabPlacement> Placements) : Query<FallbackTabIndex> {
    #region Actions - Answering

    /// A draft Space's fallback tab, by its tabs' placements.
    internal override FallbackTabIndex Answer(CrestApp app) {
        return new(TabPlacement.Fallback(Placements));
    }

    #endregion
}
