using CrestCore.Contracts;

namespace CrestCore.Domain;

#region Types

public sealed record SplitJoin(Guid SelectedTab, IReadOnlyList<(Guid Source, Guid Copy)> Copies);

#endregion

/// A Space's organization while one edit applies to it: its tabs, folders, split
/// metadata and the tabs the edit archives. It is restored from the Space's stored
/// records and captured back into them, independent of profiles, authorization and
/// live pages. The archive holds only what this edit adds; existing archive records
/// stay with the Space.
public sealed partial class BrowserTabCollection {
    #region Variables

    public const int MaximumTabs = 5000;
    /// The most characters a Space or folder name holds.
    public const int MaximumNameLength = 200;
    private readonly List<BrowserTab> tabs = [];
    private readonly List<FolderState> folders = [];
    private readonly List<SplitGroupState> splitGroups = [];
    private readonly List<ArchivedTabState> archive = [];
    public IReadOnlyList<BrowserTab> Tabs => tabs.AsReadOnly();
    public IReadOnlyList<FolderState> Folders => folders.AsReadOnly();
    public IReadOnlyList<SplitGroupState> SplitGroups => splitGroups.AsReadOnly();
    public IReadOnlyList<ArchivedTabState> Archive => archive.AsReadOnly();
    public IReadOnlyList<TabState> TabStates => [.. tabs.Select(tab => tab.State)];

    #endregion

    #region Actions - Persistence

    /// The Space's organization for one edit.
    public static BrowserTabCollection Restore(SpaceState space) {
        ArgumentNullException.ThrowIfNull(space);
        return Restore(space.Tabs, space.Folders, space.SplitGroups);
    }

    /// The Space after the edit: its organization replaced and the tabs the
    /// edit archived added after the ones it already had.
    public SpaceState Capture(SpaceState space) {
        ArgumentNullException.ThrowIfNull(space);
        return space with {
            Tabs = TabStates,
            Folders = [.. folders],
            SplitGroups = [.. splitGroups],
            ArchivedTabs = [.. space.ArchivedTabs, .. archive]
        };
    }

    public static BrowserTabCollection Restore(IEnumerable<TabState> tabs, IEnumerable<FolderState> folders,
        IEnumerable<SplitGroupState> splitGroups) {
        var collection = new BrowserTabCollection();
        collection.tabs.AddRange(tabs.Select(BrowserTab.Restore));
        collection.folders.AddRange(folders);
        collection.splitGroups.AddRange(splitGroups);
        new FolderTree(collection.folders).Validate();
        collection.RepairSplitMembership();
        return collection;
    }

    #endregion

    #region Actions - Sections

    /// Where a later section starts: the first tab whose section comes after
    /// `placement`'s, or the end.
    private static int NextSection(List<BrowserTab> tabs, TabPlacement placement) {
        int index = tabs.FindIndex(tab => tab.Placement.Rank > placement.Rank);
        return index < 0 ? tabs.Count : index;
    }

    /// The tab a Space selects once its selection is gone.
    private Guid? FallbackSelection() =>
        TabPlacement.Fallback([.. tabs.Select(tab => tab.Placement)]) is { } index ? tabs[index].Id : null;

    #endregion

    #region Mutators

    public BrowserTab Tab(Guid id) => tabs.Find(t => t.Id == id) ?? throw new Rejected(new UnknownTab(id));

    /// The folder with this identity, or `UnknownFolder`.
    private FolderState KnownFolder(Guid id) => folders.Find(f => f.Id == id) ?? throw new Rejected(new UnknownFolder(id));

    #endregion
}
