using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One repair of a detached session under way: the identities it has given
/// Spaces, profiles and tabs so far, so every one is its own, and where each
/// repaired tab's native assets come from. Each Space is either kept as it was,
/// while its deletion is under way, or repaired: its folder tree, its tabs'
/// sections, folders and saved addresses, its split runs and metadata, its
/// archive and its history each mended in turn.
internal sealed class SessionRepair(IIdSource ids, DateTimeOffset now) {
    #region Static Variables

    /// What the Space made for an empty session is called and wears when the
    /// native caller supplies none.
    private const string BlankSpaceName = "Space 1";
    private const string BlankSpaceSymbol = "square.grid.2x2.fill";

    #endregion

    #region Variables

    private readonly RuntimeIdentityRegistry spaceIds = new(ids);
    private readonly RuntimeIdentityRegistry profiles = new(ids);
    private readonly RuntimeIdentityRegistry tabIds = new(ids);
    private readonly List<NativeSessionMaintenance.TabOrigin> assets = [];

    /// Where each tab repaired so far takes its native assets from.
    internal IReadOnlyList<NativeSessionMaintenance.TabOrigin> Origins => assets;

    #endregion

    #region Actions - Spaces

    /// The Space a session that would keep none starts with: `emptySpace`, or
    /// a blank one, with identities of its own and one Start Page.
    internal static SpaceState Empty(SpaceState? emptySpace, IIdSource ids, DateTimeOffset now) =>
        (emptySpace ?? BlankSpace()) with {
            Id = ids.Next(),
            ProfileId = ids.Next(),
            Folders = [],
            Tabs = [TabState.NewStartPage(ids.Next(), now)],
            SplitGroups = [],
            ArchivedTabs = [],
            History = []
        };

    /// `space`, at `spaceIndex`, kept exactly as it was while its cleanup is
    /// under way, its identities claimed so no other Space can take them.
    internal SpaceState Kept(SpaceState space, int spaceIndex) {
        if (spaceIds.Claim(space.Id) != space.Id || profiles.Claim(space.ProfileId) != space.ProfileId)
            throw new BrowserRuleException(BrowserRule.InvalidDeletionIntent);
        foreach (var (tab, tabIndex) in space.Tabs.Select((tab, index) => (tab, index))) {
            _ = tabIds.Claim(tab.Id);
            assets.Add(new(spaceIndex, tabIndex, space.Id, tab.Id));
        }
        foreach (var archived in space.ArchivedTabs.Where(archived => !archived.Tab.IsStartPage)) _ = tabIds.Claim(archived.Tab.Id);
        return space;
    }

    /// `space`, at `spaceIndex`, with identities of its own and every repair
    /// made: its folder tree, its tabs, its split runs, its archive, its
    /// history and its split metadata.
    internal SpaceState Repaired(SpaceState space, int spaceIndex) {
        var identified = space with { Id = spaceIds.Claim(space.Id), ProfileId = profiles.Claim(space.ProfileId) };
        var folders = Folders(space);
        var tabs = Tabs(space, spaceIndex, folders);
        var groups = SplitMember.Repair(tabs.Select(tab => new SplitMember(tab.SplitGroupId, tab.Placement, tab.FolderId)).ToArray());
        return identified with {
            Folders = folders,
            Tabs = [.. tabs.Select((tab, index) => tab with { SplitGroupId = groups[index] })],
            ArchivedTabs = Archive(space),
            History = [.. space.History.Take(HistoryEntryState.MaximumEntries)],
            SplitGroups = SplitGroupState.Merged(space.SplitGroups)
        };
    }

    #endregion

    #region Actions - Repairs

    /// The Space's folders, each with an identity of its own in the Space, as
    /// a bounded tree in preorder.
    private IReadOnlyList<FolderState> Folders(SpaceState space) {
        var folderIds = new RuntimeIdentityRegistry(ids);
        return FolderTree.RepairPreorder(space.Folders.Select(folder => folder with { Id = folderIds.Claim(folder.Id) }).ToArray());
    }

    /// The Space's tabs, each with an identity of its own, in the section that
    /// still holds it, in a folder only of that section, with a saved address
    /// only when it is saved, and a Start Page when none is left.
    private List<TabState> Tabs(SpaceState space, int spaceIndex, IReadOnlyList<FolderState> folders) {
        var locations = folders.ToDictionary(folder => folder.Id, folder => folder.Location);
        var counts = new Dictionary<TabPlacement, int>();
        var tabs = space.Tabs.Select((tab, tabIndex) => {
            var id = tabIds.Claim(tab.Id);
            assets.Add(new(spaceIndex, tabIndex, space.Id, tab.Id));
            counts[tab.Placement] = counts.GetValueOrDefault(tab.Placement) + 1;
            var placement = tab.Placement.Fitting(counts[tab.Placement]);
            var folder = placement.HoldsFolders && tab.FolderId is { } folderId
                && locations.TryGetValue(folderId, out var location) && location == placement ? tab.FolderId : null;
            return (tab with {
                Id = id,
                Placement = placement,
                SavedUrl = placement.IsDurable ? tab.SavedUrl ?? tab.Url : null,
                FolderId = folder
            }).Normalized();
        }).ToList();
        if (tabs.Count == 0) tabs.Add(TabState.NewStartPage(tabIds.Claim(ids.Next()), now));
        return tabs;
    }

    /// The Space's archived tabs but its Start Pages, each with an identity of
    /// its own, as current tabs in no folder or split.
    private List<ArchivedTabState> Archive(SpaceState space) => [.. space.ArchivedTabs.Where(archived => !archived.Tab.IsStartPage)
        .Select(archived => archived with {
            Tab = (archived.Tab with {
                Id = tabIds.Claim(archived.Tab.Id),
                Placement = TabPlacement.Current,
                SavedUrl = null,
                FolderId = null,
                SplitGroupId = null
            }).Normalized()
        })];

    #endregion

    #region Mutators

    /// The Space an empty session starts with when the native caller supplies none.
    private static SpaceState BlankSpace() => new(Guid.Empty, Guid.Empty,
        new(BlankSpaceName, BlankSpaceSymbol, SpaceAccent.Indigo, null, StoredSessionCodec.DefaultBrowsingPreferences,
            StoredSessionCodec.DefaultCredentialPreferences, SpaceAccessPolicy.Open, true, null), [], [], [], [], []);

    #endregion
}
