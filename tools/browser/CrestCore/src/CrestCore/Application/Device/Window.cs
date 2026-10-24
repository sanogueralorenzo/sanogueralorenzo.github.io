using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One of this device's windows and what it shows: the Space on screen, the
/// tab it shows in each Space it has shown (or none), the column shares of the
/// split groups it resized, and each Space's recently shown tabs, which choose
/// the tab to show when the shown one is dismissed. The device serializes
/// every call.
internal sealed class Window {
    #region Variables

    /// A split group renders only with at least this many members.
    private const int MinimumSplitMembers = 2;

    /// The tab shown in each Space; null when the window shows none there.
    private readonly Dictionary<Guid, Guid?> tabs;
    private readonly Dictionary<Guid, IReadOnlyList<double>> shares;
    /// Each Space's shown tabs, most recent last. Kept in memory only.
    private readonly Dictionary<Guid, List<Guid>> recent;

    public Guid Id { get; }
    public Guid WorkspaceId { get; }
    /// Whether the window keeps its record in the device store.
    public bool Saved { get; }
    public Guid ShownSpaceId { get; private set; }

    /// The tab the window shows in each Space it has shown.
    public IEnumerable<ShownTab> ShownTabs => tabs.Select(entry => new ShownTab(entry.Key, entry.Value));

    #endregion

    #region Constructors

    private Window(Guid id, Guid workspaceId, bool saved, Guid shownSpaceId, Dictionary<Guid, Guid?> tabs,
        Dictionary<Guid, IReadOnlyList<double>> shares, Dictionary<Guid, List<Guid>> recent) {
        Id = id;
        WorkspaceId = workspaceId;
        Saved = saved;
        ShownSpaceId = shownSpaceId;
        this.tabs = tabs;
        this.shares = shares;
        this.recent = recent;
    }

    /// A window that shows what `record` kept.
    public static Window Restoring(SavedWindow record, Guid workspaceId) => new(record.Id, workspaceId, saved: true,
        record.ShownSpaceId, record.Tabs.ToDictionary(tab => tab.SpaceId, tab => tab.TabId),
        record.Shares.ToDictionary(group => group.GroupId, group => group.Shares), []);

    /// A window that starts as `other` shows, without its split columns.
    public static Window Copying(Window other, Guid id, bool saved) =>
        new(id, other.WorkspaceId, saved, other.ShownSpaceId, new(other.tabs), [], []);

    /// A window on `session`'s launch Space: its default Space unless that is
    /// being deleted, else the first Space. `legacyTabs` are the tabs an older
    /// release kept in the session, which a window without a record adopts.
    public static Window Launching(Guid id, Guid workspaceId, bool saved, SessionState session,
        IReadOnlyDictionary<Guid, Guid> legacyTabs) {
        var launch = LaunchSpace(session);
        var window = new Window(id, workspaceId, saved, launch?.Id ?? Guid.Empty,
            legacyTabs.Where(entry => session.Spaces.Any(space => space.Id == entry.Key && Contains(space, entry.Value)))
                .ToDictionary(entry => entry.Key, entry => (Guid?)entry.Value), [], []);
        if (launch is not null) window.ShowSpace(launch);
        return window;
    }

    /// The Space a window without a record opens on over `session`: its
    /// default Space unless that is being deleted, else the first Space, or
    /// none while every Space is going.
    public static SpaceState? LaunchSpace(SessionState session) {
        var available = Showable(session).ToArray();
        return available.FirstOrDefault(space => space.Id == session.DefaultSpaceId) ?? available.FirstOrDefault();
    }

    /// What the window shows over `session`, as the platform reads it: what
    /// it chose to show, the cards its content shows for the tab it shows, and
    /// the commands it cannot run now. A window over a private workspace keeps
    /// nothing, which its commands read.
    public WindowState State(SessionState session, bool isPrivate) {
        ArgumentNullException.ThrowIfNull(session);
        var space = Showable(session).FirstOrDefault(candidate => candidate.Id == ShownSpaceId);
        var shown = space is not null && Tab(space.Id) is { } tabId ? space.Tabs.FirstOrDefault(tab => tab.Id == tabId) : null;
        IReadOnlyList<ShownCards> cards = [.. session.Spaces.OrderBy(candidate => candidate.Id)
            .Select(candidate => Tab(candidate.Id) is { } tabId && Contains(candidate, tabId) ? Cards(candidate, tabId) : null)
            .OfType<ShownCards>()];
        int shownCards = shown is null ? 0 : cards.First(candidate => candidate.SpaceId == ShownSpaceId).TabIds.Count;
        var facts = new WindowCommandFacts(space is not null, isPrivate, shown, space?.ArchivedTabs.Count > 0,
            space is not null && shown is not null && space.SplitCandidate(shown.Id) is not null, shownCards);
        return new(Id, WorkspaceId, ShownSpaceId,
            [.. tabs.OrderBy(entry => entry.Key).Select(entry => new ShownTab(entry.Key, entry.Value))],
            [.. shares.OrderBy(entry => entry.Key).Select(entry => new SplitColumnShares(entry.Key, entry.Value))],
            cards, [.. ShortcutCommand.All.Where(command => !command.IsAvailable(facts))]);
    }

    /// The tabs the window's content shows on screen over `session`: the cards
    /// of the Space it shows, or none.
    public IReadOnlyList<Guid> OnScreen(SessionState session) {
        ArgumentNullException.ThrowIfNull(session);
        var space = session.Spaces.FirstOrDefault(candidate => candidate.Id == ShownSpaceId);
        return space is not null && Tab(space.Id) is { } tabId && Contains(space, tabId) ? Cards(space, tabId).TabIds : [];
    }

    /// The tabs a window's content shows for `shown` in `space`, side by
    /// side: the members of the split its sidebar row shows, in order, or
    /// `shown` alone.
    private static ShownCards Cards(SpaceState space, Guid shown) {
        foreach (var list in space.Sidebar.Lists)
            foreach (var row in list.Rows)
                if (row.Kind.GroupsTabs && row.Members.Contains(shown)) return new(space.Id, [.. row.Members], row.Id);
        return new(space.Id, [shown], null);
    }

    /// A copy a command reads while the device keeps editing the window.
    public Window Snapshot() => new(Id, WorkspaceId, Saved, ShownSpaceId, new(tabs), new(shares),
        recent.ToDictionary(entry => entry.Key, entry => new List<Guid>(entry.Value)));

    #endregion

    #region Actions - Showing

    /// The tab the window shows in a Space, or null when it shows none there.
    public Guid? Tab(Guid spaceId) => tabs.GetValueOrDefault(spaceId);

    /// Shows `space`, on the tab the window showed there while it still
    /// exists, else on the Space's fallback tab.
    public void ShowSpace(SpaceState space) {
        ShownSpaceId = space.Id;
        if (!Contains(space, tabs.GetValueOrDefault(space.Id))) tabs[space.Id] = FallbackTab(space);
        Remember(space.Id);
    }

    /// Moves the window to `spaceId` and keeps what it shows there, even nothing.
    public void MoveTo(Guid spaceId) => ShownSpaceId = spaceId;

    /// Keeps only the Space the window shows: it shows no tab anywhere until
    /// one is chosen, and keeps no split columns or history.
    public void ForgetTabs() {
        tabs.Clear();
        shares.Clear();
        recent.Clear();
    }

    /// Shows `tabId` in its Space, moving the window there when `moves`, or
    /// shows nothing in `spaceId` and leaves the window where it is.
    public void ShowTab(Guid spaceId, Guid? tabId, bool moves) {
        if (moves && tabId is not null) ShownSpaceId = spaceId;
        tabs[spaceId] = tabId;
        Remember(spaceId);
    }

    /// Applies what a command chose for this window to show next.
    public void Apply(WindowFollowUp followUp) {
        foreach (var (spaceId, tabId) in followUp.Dismissed)
            if (recent.TryGetValue(spaceId, out var history)) history.Remove(tabId);
        foreach (var (spaceId, tabId) in followUp.Tabs) {
            tabs[spaceId] = tabId;
            Remember(spaceId);
        }
        if (followUp.SpaceId is { } space) ShownSpaceId = space;
    }

    /// The tab to show after `dismissed` leaves `space`: the tab the window
    /// showed there before it, while `available` still holds it. The history
    /// forgets `dismissed`, and forgets everything when nothing qualifies.
    public Guid? DismissalFallback(Guid spaceId, Guid dismissed, IReadOnlySet<Guid> available) {
        if (!recent.TryGetValue(spaceId, out var history)) return null;
        history.Remove(dismissed);
        if (history.Count > 0 && available.Contains(history[^1])) return history[^1];
        history.Clear();
        return null;
    }

    /// Repairs the window after `session` changed under it: a tab that is gone shows nothing, a
    /// Space that is gone or being deleted gives way to the first remaining
    /// one on its fallback tab, split shares survive only while their group
    /// renders with as many columns, and the history forgets what is gone.
    public void Repair(SessionState session) {
        var spaces = session.Spaces.ToDictionary(space => space.Id);
        foreach (var (spaceId, tabId) in tabs.ToArray()) {
            if (!spaces.TryGetValue(spaceId, out var space)) tabs.Remove(spaceId);
            else if (tabId is not null && !Contains(space, tabId)) tabs[spaceId] = null;
        }
        if (!Showable(session).Any(space => space.Id == ShownSpaceId) && Showable(session).FirstOrDefault() is { } fallback)
            ShowSpace(fallback);
        foreach (var groupId in shares.Keys.ToArray())
            if (!session.Spaces.Any(space => RenderedColumns(space, groupId) == shares[groupId].Count)) shares.Remove(groupId);
        foreach (var (spaceId, history) in recent.ToArray()) {
            if (!spaces.TryGetValue(spaceId, out var space)) recent.Remove(spaceId);
            else history.RemoveAll(tabId => !Contains(space, tabId));
        }
        foreach (var spaceId in tabs.Keys) Remember(spaceId);
    }

    /// Records one split group's column shares, normalized. Answers false for
    /// shares that cannot describe columns.
    public bool Resize(Guid groupId, IReadOnlyList<double> requested) {
        if (SplitShares(requested) is not { } normalized) return false;
        shares[groupId] = normalized;
        return true;
    }

    /// The record the device store keeps for this window.
    public SavedWindow Record(long used) => new(Id, ShownSpaceId,
        [.. tabs.Select(entry => new ShownTab(entry.Key, entry.Value))],
        [.. shares.Select(entry => new SplitColumnShares(entry.Key, entry.Value))], used);

    private void Remember(Guid spaceId) {
        if (tabs.GetValueOrDefault(spaceId) is not { } tabId) return;
        if (!recent.TryGetValue(spaceId, out var history)) recent[spaceId] = history = [];
        if (history.Count > 0 && history[^1] == tabId) return;
        history.Remove(tabId);
        history.Add(tabId);
    }

    #endregion

    #region Actions - Rules

    /// The tab a Space shows when no window chose one: the first open tab,
    /// else the first pinned one, else the first tab.
    public static Guid? FallbackTab(SpaceState space) =>
        TabPlacement.Fallback([.. space.Tabs.Select(tab => tab.Placement)]) is { } index ? space.Tabs[index].Id : null;

    /// Shares that describe a split's columns, normalized to sum to one, or
    /// null: there must be at least one and no more than a split holds, each a
    /// finite share greater than zero and at most the whole.
    public static IReadOnlyList<double>? SplitShares(IReadOnlyList<double> requested) {
        ArgumentNullException.ThrowIfNull(requested);
        const double tolerance = 0.0001;
        if (requested.Count is 0 or > BrowserTabCollection.MaximumSplitMembers
            || requested.Any(value => !double.IsFinite(value) || value <= 0 || value > 1)) return null;
        double total = requested.Sum();
        return Math.Abs(total - 1) <= tolerance ? [.. requested] : [.. requested.Select(value => value / total)];
    }

    /// The Spaces a window may show, in the session's order: every one not being deleted.
    internal static IEnumerable<SpaceState> Showable(SessionState session) =>
        session.Spaces.Where(space => session.SpaceDeletions.All(deletion => deletion.SpaceId != space.Id));

    private static bool Contains(SpaceState space, Guid? tabId) => tabId is { } id && space.Tabs.Any(tab => tab.Id == id);

    /// How many columns a split group renders with in `space`: the length of
    /// its first contiguous run of tabs, when that run can render.
    private static int RenderedColumns(SpaceState space, Guid groupId) {
        int start = space.Tabs.ToList().FindIndex(tab => tab.SplitGroupId == groupId);
        if (start < 0) return 0;
        int length = space.Tabs.Skip(start).TakeWhile(tab => tab.SplitGroupId == groupId).Count();
        return length >= MinimumSplitMembers ? length : 0;
    }

    #endregion
}
