namespace CrestCore.Contracts;

public sealed record ImportReviewSpace(SpaceState Source, bool Included, Guid? DestinationId, SpaceCustomization Customization,
    IReadOnlyList<Guid> IncludedTabIds, IReadOnlyList<Guid> DuplicateTabIds, IReadOnlyList<Guid> MatchedTabIds,
    IReadOnlyList<TabPlacementChoice> Placements, IReadOnlyList<ImportExtension> Extensions,
    IReadOnlyList<string> IncludedExtensionIds) {
    #region Variables

    /// The name the Space shows and takes once imported: the one chosen,
    /// trimmed, or "Untitled Space" for a blank one.
    [Resolved]
    public string ShownName => SpaceCustomization.Resolved(Customization.Name);


    /// The extensions that install in the Space's destination once it is
    /// imported: those the person left on, in the order the Space offers them,
    /// when the Space comes in.
    [Resolved]
    public IReadOnlyList<ImportExtension> BroughtExtensions => Included
        ? [.. Extensions.Where(extension => IncludedExtensionIds.Contains(extension.ExtensionId))] : [];

    /// Whether the Space comes in as a new Space, taking room in the
    /// workspace, rather than joining one it holds.
    internal bool MakesNewSpace => Included && DestinationId is null;

    #endregion

    #region Actions - Review

    internal static ImportReviewSpace Started(SpaceState space, SpaceState? match, bool included,
        IReadOnlyList<ImportExtension> offered) {
        var duplicates = match is null ? [] : space.TabsAlsoIn(match).ToHashSet();
        return new(space, included, match?.Id, match?.Customization ?? space.Customization,
            included ? [.. space.Tabs.Where(tab => !duplicates.Contains(tab.Id)).Select(tab => tab.Id)] : [], [], [], [],
            offered, [.. offered.Select(extension => extension.ExtensionId)]);
    }

    /// The Space with what joining `destination` means: its tabs the
    /// destination already holds, and, when it comes in, the destination's
    /// tabs it matches.
    internal ImportReviewSpace Analyzed(SpaceState? destination) => this with {
        DuplicateTabIds = destination is null ? [] : Source.TabsAlsoIn(destination),
        MatchedTabIds = destination is null || !Included ? [] : destination.TabsAlsoIn(Source)
    };

    /// `ids` in the order the Space holds its tabs.
    internal Guid[] Ordered(IEnumerable<Guid> ids) {
        var chosen = ids.ToHashSet();
        return [.. Source.Tabs.Select(tab => tab.Id).Where(chosen.Contains)];
    }

    #endregion
}
