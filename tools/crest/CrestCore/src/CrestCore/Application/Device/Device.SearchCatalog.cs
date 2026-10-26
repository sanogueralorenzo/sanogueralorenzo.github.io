using CrestCore.Contracts;

namespace CrestCore.Application;

#region Types

/// A Space the first restore of the catalog sets to follow the default search
/// or its suggestions, where it already chose what the default became.
internal sealed record SearchFollower(Guid WorkspaceId, Guid SpaceId, SearchProvider? Provider, bool? SuggestionsEnabled);

#endregion

/// This device's search catalog, which the device store keeps and never
/// syncs. Until the platform first restores it for the device's language and
/// region, the device offers what a device that never chose does.
internal sealed partial class Device {
    #region Variables

    /// The catalog the person keeps, or null before the platform first
    /// restored it. Read without the device lock, as it is replaced whole.
    private volatile SearchCatalog? searchCatalog;

    /// The catalog the device offers without keeping it while the session
    /// that keeps its preferences is still the disposable seed a first launch
    /// made, or null. Read without the device lock, as it is replaced whole.
    private volatile SearchCatalog? provisionalCatalog;

    /// The search providers the device offers.
    internal SearchCatalog SearchCatalog => searchCatalog ?? provisionalCatalog ?? SearchCatalog.Starting(language: null, region: null);

    #endregion

    #region Actions - Search intents

    /// Runs one search catalog intent, publishing the catalog when it changed.
    public void Handle(SearchCatalogIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Keeps the catalog `revise` makes of the device's own and publishes it
    /// when it changed. Throws `Rejected` from `revise`.
    internal void ReviseSearchCatalog(ChangeFeed changes, Func<SearchCatalog, SearchCatalog> revise) {
        lock (gate) Keep(revise(SearchCatalog), changes);
    }

    /// Keeps the catalog for a device in `language` and `region` and publishes
    /// it. The first time, once the session that keeps the device's
    /// preferences is open, the device starts from the built-ins, adds the
    /// engines its Spaces carry and makes the engine and suggestions most of
    /// them chose the default, and answers the Spaces that chose them, which
    /// then follow the default. Before that session is open it publishes the
    /// built-ins and keeps nothing, so the first restore after it opens still
    /// carries what the Spaces chose. While that session is still the
    /// disposable seed it offers what the seed carries and keeps nothing
    /// either, so a device whose first launch takes the cloud's Spaces in
    /// place of the seed takes the default those Spaces follow.
    internal IReadOnlyList<SearchFollower> RestoreSearchCatalog(ChangeFeed changes, string? language, string? region) {
        lock (gate) {
            if (searchCatalog is { } kept) {
                var located = kept.Locating(language, region);
                if (located.Equals(kept)) changes.Publish(SearchCatalogChanged.Of(kept));
                else Keep(located, changes);
                return [];
            }
            var starting = SearchCatalog.Starting(language, region);
            if (Carried(starting) is not var (catalog, followers, isSeed)) {
                changes.Publish(SearchCatalogChanged.Of(starting));
                return [];
            }
            if (isSeed) {
                provisionalCatalog = catalog;
                changes.Publish(SearchCatalogChanged.Of(catalog));
                return [];
            }
            Keep(catalog, changes, forces: true);
            return followers;
        }
    }

    /// `starting` with what the Spaces of the session that keeps the device's
    /// preferences chose before the device kept a catalog, and the Spaces that
    /// chose the default it makes; null while no such session is open. When a
    /// Space already follows a default, another device chose it first: this
    /// device takes the default those Spaces carry and leaves every Space as
    /// it is. `IsSeed` says the session is still the disposable seed. The
    /// caller holds the device lock.
    private (SearchCatalog Catalog, IReadOnlyList<SearchFollower> Followers, bool IsSeed)? Carried(SearchCatalog starting) {
        var (workspaceId, authority) = persistentWorkspace is { } kept && workspaces.TryGetValue(kept, out var stored) ? (kept, stored)
            : workspaces.FirstOrDefault(entry => entry.Value.Kind.KeepsAppPreferences) is { Value: not null } seeded ? (seeded.Key, seeded.Value)
            : (Guid.Empty, null);
        if (authority is null) return null;
        var spaces = authority.Current.Spaces.Select(space => (space.Id, Browsing: space.Settings.BrowsingPreferences)).ToList();
        var catalog = starting.Adopting(spaces.SelectMany(space => space.Browsing.CustomSearchProviders));
        var following = spaces.Where(space => space.Browsing.FollowsDefaultSearch).ToList();
        var chose = following.Count > 0 ? following : spaces;
        // A following Space carries the default it followed in its own choice.
        var engines = chose.Select(space => catalog.For(space.Browsing with { FollowsDefaultSearch = false }, isPrivate: false))
            .Where(provider => provider.Kind.CanBeDefault && catalog.Named(provider.Name) is not null).ToList();
        if (engines.Count > 0) catalog = catalog.Choosing(engines.GroupBy(provider => provider.Name).MaxBy(group => group.Count())!.First());
        var suggesting = following.Count > 0 ? spaces.Where(space => space.Browsing.FollowsDefaultSuggestions).ToList() : spaces;
        if (suggesting.Count > 0)
            catalog = catalog.Suggesting(suggesting.Count(space => space.Browsing.SearchSuggestionsEnabled) * 2 > suggesting.Count);
        bool isSeed = authority.Current.DisposableSeedMarker is not null;
        if (following.Count > 0) return (catalog, [], isSeed);
        List<SearchFollower> followers = [];
        foreach (var (spaceId, browsing) in spaces) {
            var provider = catalog.For(browsing, isPrivate: false);
            bool followsSearch = provider.Name == catalog.Default.Name;
            bool followsSuggestions = browsing.SearchSuggestionsEnabled == catalog.SuggestionsEnabled;
            if (followsSearch || followsSuggestions)
                followers.Add(new(workspaceId, spaceId, followsSearch ? null : provider,
                    followsSuggestions ? null : browsing.SearchSuggestionsEnabled));
        }
        return (catalog, followers, isSeed);
    }

    /// Keeps `revised`, saved and published when it differs from what the
    /// device holds, or when `forces`. The caller holds the device lock.
    private void Keep(SearchCatalog revised, ChangeFeed changes, bool forces = false) {
        if (!forces && searchCatalog is not null && searchCatalog.Equals(revised)) return;
        searchCatalog = revised;
        provisionalCatalog = null;
        storage?.EnqueueDevice(Records());
        changes.Publish(SearchCatalogChanged.Of(revised));
    }

    #endregion
}
