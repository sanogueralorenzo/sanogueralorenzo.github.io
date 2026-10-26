using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// <summary>
/// A Space: one browsing profile with its <see cref="Settings"/>, its tabs, folders
/// and split metadata, and the history and archive it keeps. Space and profile are
/// one to one.
/// </summary>
public sealed record SpaceState(
    Guid Id,
    Guid ProfileId,
    SpaceSettings Settings,
    IReadOnlyList<FolderState> Folders,
    IReadOnlyList<TabState> Tabs,
    IReadOnlyList<SplitGroupState> SplitGroups,
    IReadOnlyList<ArchivedTabState> ArchivedTabs,
    IReadOnlyList<HistoryEntryState> History) {
    #region Types

    /// An outline with the lists it was resolved from.
    private sealed class ResolvedSidebar(IReadOnlyList<TabState> tabs, IReadOnlyList<FolderState> folders, SidebarOutline outline) {
        public SidebarOutline? Outline(IReadOnlyList<TabState> currentTabs, IReadOnlyList<FolderState> currentFolders) =>
            ReferenceEquals(tabs, currentTabs) && ReferenceEquals(folders, currentFolders) ? outline : null;
    }

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<FolderState> Folders {
        get;
        init => field = [.. value];
    } = [.. Folders];

    public IReadOnlyList<TabState> Tabs {
        get;
        init => field = [.. value];
    } = [.. Tabs];

    public IReadOnlyList<SplitGroupState> SplitGroups {
        get;
        init => field = [.. value];
    } = [.. SplitGroups];

    public IReadOnlyList<ArchivedTabState> ArchivedTabs {
        get;
        init => field = [.. value];
    } = [.. ArchivedTabs];

    public IReadOnlyList<HistoryEntryState> History {
        get;
        init => field = [.. value];
    } = [.. History];


    /// <summary>What the Space's sidebar lists, resolved from its tabs and folders. It is
    /// resolved once for the lists it reads; a copy made with <c>with</c> keeps it only
    /// while it holds the same tab and folder lists.</summary>
    [Resolved]
    public SidebarOutline Sidebar {
        get {
            if (sidebar?.Outline(Tabs, Folders) is { } outline) return outline;
            var resolved = SidebarOutline.Of(Tabs, Folders);
            sidebar = new ResolvedSidebar(Tabs, Folders, resolved);
            return resolved;
        }
    }

    private ResolvedSidebar? sidebar;

    #endregion

    #region Actions - Sidebar

    /// <summary>Whether the Space's sidebar shows the section's rows: a section a person
    /// may collapse shows them while the Space keeps its saved tabs expanded.</summary>
    public bool Shows(TabPlacement section) {
        ArgumentNullException.ThrowIfNull(section);
        return !section.IsCollapsible || Settings.IsSavedTabsExpanded;
    }

    /// <summary>The rows a person steps through in the Space's sidebar, in order; see
    /// <see cref="SidebarOutline.Stops"/>.</summary>
    public IReadOnlyList<SidebarRow> Stops() => Sidebar.Stops(Folders, Shows);

    /// <summary>The tab one step in <paramref name="direction"/> from the shown tab shows,
    /// or null; see <see cref="SidebarOutline.Step"/>.</summary>
    public Guid? Step(Guid shownTabId, AdjacentDirection direction) => Sidebar.Step(shownTabId, direction, Folders, Shows);

    /// <summary>The tab a swipe in <paramref name="direction"/> from the shown tab reaches,
    /// or null at either end; see <see cref="SidebarOutline.Swipe"/>.</summary>
    public Guid? Swipe(Guid shownTabId, AdjacentDirection direction) => Sidebar.Swipe(shownTabId, direction, Folders, Shows);

    /// <summary>The tab "Split With Next Tab" would add to the split of the shown tab
    /// <paramref name="shownTabId"/>: the first tab row after the row that holds it, in
    /// the same list of the sidebar, whose tab is in no split; or null. A Start Page,
    /// which the sidebar lists nowhere, has none.</summary>
    public Guid? SplitCandidate(Guid shownTabId) {
        foreach (var list in Sidebar.Lists) {
            int shown = -1;
            for (int index = 0; index < list.Rows.Count && shown < 0; index++)
                if (!list.Rows[index].Kind.OpensList && list.Rows[index].Members.Contains(shownTabId)) shown = index;
            if (shown < 0) continue;
            var grouped = Tabs.Where(tab => tab.SplitGroupId is not null).Select(tab => tab.Id).ToHashSet();
            return list.Rows.Skip(shown + 1).FirstOrDefault(row => row.Kind == SidebarRowKind.Tab && !grouped.Contains(row.Id))?.Id;
        }
        return null;
    }

    #endregion

    #region Actions - Imports

    /// The name and look the Space has, as a review or a setup offers them.
    internal SpaceCustomization Customization => new(Settings.Name, Settings.Symbol, Settings.Accent, Settings.Look);

    /// The first of `destinations` not in `joined` whose name matches this
    /// Space's. Two Space names match on letters and digits only, ignoring
    /// case, accents and width; a name with neither never matches.
    internal SpaceState? Joining(IReadOnlyList<SpaceState> destinations, IReadOnlySet<Guid> joined) {
        string key = FolderState.MatchKey(Settings.Name);
        return key.Length == 0 ? null
            : destinations.FirstOrDefault(existing => !joined.Contains(existing.Id) && FolderState.MatchKey(existing.Settings.Name) == key);
    }

    /// This Space's tabs at an address `other` holds a tab at.
    internal Guid[] TabsAlsoIn(SpaceState other) {
        var keys = other.TabKeys();
        return [.. Tabs.Where(tab => tab.Url is not null && keys.Contains(UrlKey(tab.Url))).Select(tab => tab.Id)];
    }

    private HashSet<string> TabKeys() =>
        Tabs.Where(tab => tab.Url is not null).Select(tab => UrlKey(tab.Url!)).ToHashSet(StringComparer.Ordinal);

    /// The key two tab addresses match on: the address a history visit would
    /// record, or the address itself when history would not record it.
    private static string UrlKey(string url) => new WebAddress(url).Normalized ?? url;

    #endregion

    #region Actions - Settings

    /// The Space with `settings`, or itself when it already has them, so an
    /// edit that changes nothing publishes nothing.
    internal SpaceState Configured(SpaceSettings settings) => settings == Settings ? this : this with { Settings = settings };

    #endregion

    #region Actions - History and archive

    /// The Space without the history entries `removes` picks, or itself when
    /// it picks none.
    internal SpaceState WithoutHistory(Func<HistoryEntryState, bool> removes) => WithoutHistory((entry, _) => removes(entry));

    /// The Space without the history entries `removes` picks by entry and
    /// position, or itself when it picks none.
    internal SpaceState WithoutHistory(Func<HistoryEntryState, int, bool> removes) {
        IReadOnlyList<HistoryEntryState> kept = [.. History.Where((entry, index) => !removes(entry, index))];
        return kept.Count == History.Count ? this : this with { History = kept };
    }

    /// The Space without the history and archive entries older at `now` than
    /// it keeps them, or itself when none are.
    internal SpaceState Retained(DateTimeOffset now) {
        var retention = Settings.BrowsingPreferences.DataRetention;
        var seconds = StoredSessionCodec.Seconds(now);
        var space = this;
        if (retention.History.Lifetime is { } history) {
            var expired = DataRetention.Expired(Seconds(History.Select(entry => entry.LastVisitedAt)), seconds,
                history.TotalSeconds).ToHashSet();
            space = space.WithoutHistory((_, index) => expired.Contains(index));
        }
        if (retention.Archive.Lifetime is { } archive) {
            var expired = DataRetention.Expired(Seconds(ArchivedTabs.Select(archived => archived.ArchivedAt)), seconds,
                archive.TotalSeconds).ToHashSet();
            if (expired.Count > 0) space = space with { ArchivedTabs = [.. ArchivedTabs.Where((_, index) => !expired.Contains(index))] };
        }
        return space;
    }

    /// The Space with its open tabs unused at `now` for longer than its
    /// cleanup lifetime archived, keeping `kept`, or itself when none are.
    internal SpaceState CleanedUp(DateTimeOffset now, IReadOnlySet<Guid>? kept) {
        if (Settings.BrowsingPreferences.CurrentTabCleanup.Lifetime is not { } lifetime) return this;
        var edited = BrowserTabCollection.Restore(this);
        edited.CleanupCurrentTabs(null, lifetime, now, kept?.ToArray());
        return Tabs.SequenceEqual(edited.TabStates) ? this : edited.Capture(this);
    }

    /// The dates as the stored format's seconds, which the removal policies read.
    private static double[] Seconds(IEnumerable<DateTimeOffset> dates) => dates.Select(StoredSessionCodec.Seconds).ToArray();

    #endregion

    #region Actions - Equality

    public bool Equals(SpaceState? other) => ReferenceEquals(this, other) || other is not null
        && Id == other.Id
        && ProfileId == other.ProfileId
        && Settings == other.Settings
        && Folders.SequenceEqual(other.Folders)
        && Tabs.SequenceEqual(other.Tabs)
        && SplitGroups.SequenceEqual(other.SplitGroups)
        && ArchivedTabs.SequenceEqual(other.ArchivedTabs)
        && History.SequenceEqual(other.History);

    public override int GetHashCode() => HashCode.Combine(Id, ProfileId, Settings.Name, Tabs.Count, Settings.AccessPolicy);

    #endregion
}
