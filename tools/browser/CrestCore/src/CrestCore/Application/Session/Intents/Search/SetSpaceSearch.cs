using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets what a Space searches with and whether it suggests searches: the
/// device's default search while `Provider` is null, the private one in a
/// private window, else `Provider`, a
/// search engine or AI assistant the device keeps or one the Space already
/// carries; and the device's default suggestions while `SuggestionsEnabled`
/// is null, else its own. A Space that searches with a provider a person
/// added carries its name and addresses, so another device or an older
/// release still searches with it; a Space that follows the default carries
/// the default the device has now, for an older release, which reads only
/// that. Refused with `UnknownSearchEngine` for a provider neither keeps, and
/// `UnsuitableDefaultSearch` for a website.
public sealed record SetSpaceSearch(Guid WorkspaceId, Guid SpaceId, SearchProvider? Provider, bool? SuggestionsEnabled)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var catalog = workspace.SearchCatalog;
        var browsing = space.Settings.BrowsingPreferences;
        bool isPrivate = workspace.Kind.IsPrivate;
        var provider = Provider is null ? catalog.DefaultFor(isPrivate) : Chosen(catalog, browsing, Provider, isPrivate);
        var searching = browsing with {
            FollowsDefaultSearch = Provider is null,
            SelectedBuiltInEngine = provider.BuiltIn,
            SelectedCustomEngineId = provider.CustomId,
            CustomSearchProviders = provider.CustomId is { } id ? Carrying(catalog, browsing, id) : [],
            FollowsDefaultSuggestions = SuggestionsEnabled is null,
            SearchSuggestionsEnabled = SuggestionsEnabled ?? catalog.SuggestionsEnabled
        };
        if (searching == browsing) return null;
        var configured = workspace.Configured(space, space.Settings with { BrowsingPreferences = searching });
        return new(NativeSessionAuthority.Replacing(turn.Basis, configured), SyncStaging.Edit);
    }

    /// The provider `chosen` names, as the device keeps it or as the Space
    /// carries it.
    private static SearchProvider Chosen(SearchCatalog catalog, BrowsingPreferences browsing, SearchProvider chosen, bool isPrivate) {
        var carried = chosen.CustomId is { } id && browsing.CustomSearchProviders.Any(provider => provider.Id == id)
            ? catalog.For(browsing with { FollowsDefaultSearch = false, SelectedBuiltInEngine = null, SelectedCustomEngineId = id }, isPrivate)
            : null;
        var known = catalog.Named(chosen.Name) ?? carried ?? throw new Rejected(new UnknownSearchEngine(chosen.CustomId));
        if (!known.Kind.CanBeDefault) throw new Rejected(new UnsuitableDefaultSearch());
        return known;
    }

    /// The definition of the added provider `id` a Space carries: the
    /// device's, else the one the Space already holds.
    private static IReadOnlyList<CustomSearchProvider> Carrying(SearchCatalog catalog, BrowsingPreferences browsing, Guid id) =>
        catalog.Custom.FirstOrDefault(provider => provider.Id == id) is { } kept ? [kept]
            : [.. browsing.CustomSearchProviders.Where(provider => provider.Id == id).Take(1)];

    #endregion
}
