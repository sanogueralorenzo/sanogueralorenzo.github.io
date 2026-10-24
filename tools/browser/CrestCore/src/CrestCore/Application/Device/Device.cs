using System.Collections.Immutable;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// What one device intent needs: where it publishes what it changed, the
/// core's time and identity source, and the pages the windows host, which
/// finishing setup hands the session it applies.
internal sealed record DeviceTurn(ChangeFeed Changes, DateTimeOffset Now, IIdSource Ids, Pages Pages);

#endregion

/// This device's windows and what each shows. It is saved in the device store
/// beside the session and never synced.
///
/// Every workspace a window may show is attached here: the persistent session
/// the core keeps, and each memory-only session (private browsing, a borrowed
/// workspace, a Quick Window). Only windows over the persistent session are
/// saved; the rest live as long as the process. After any session commit, the
/// device publishes what the session changed, then repairs the windows of the
/// workspace that changed; after every window intent it publishes each window
/// whose state changed. Attaching a session publishes it whole, and detaching
/// it publishes that it is gone.
///
/// The device lock is taken last: nothing is called on a session or on the
/// host while it is held.
internal sealed partial class Device {
    #region Variables

    /// Saved window records beyond this many are forgotten, least recently
    /// used first, as the defaults store of earlier releases did.
    public const int MaximumSavedWindows = 16;

    private readonly Lock gate = new();
    internal Lock Gate => gate;
    private readonly Dictionary<Guid, Window> open = [];
    internal Dictionary<Guid, Window> OpenWindows => open;
    /// What the device last published for each open window.
    private readonly Dictionary<Guid, WindowState> published = [];
    internal Dictionary<Guid, WindowState> PublishedWindows => published;
    private readonly Dictionary<Guid, NativeSessionAuthority> workspaces = [];
    /// The saved windows' records, open or not.
    private readonly Dictionary<Guid, SavedWindow> saved = [];
    internal Dictionary<Guid, SavedWindow> SavedWindows => saved;
    private readonly SessionStorage? storage;
    internal SessionStorage? Storage => storage;
    /// The grants every session this device shows consults.
    private readonly SpaceAccessAuthority access;
    private readonly Action<Change> announce;
    /// Asks the host for a drain on its next turn.
    private readonly Action requestTurn;
    /// Closes a borrowed workspace whose owner no longer lends its Space.
    private readonly Action<Guid> closeBorrower;
    /// The device class whose defaults the device's rules apply.
    private readonly DevicePlatform platform;
    /// The core's time, which palette memories read.
    private readonly IClock clock;

    /// The platform this device runs, whose rules memory pressure follows.
    internal DevicePlatform Platform => platform;
    /// The tabs an older release kept in the session, which a window without a
    /// record adopts during the launch that loaded them.
    private IReadOnlyDictionary<Guid, Guid> legacyTabs = new Dictionary<Guid, Guid>();
    internal IReadOnlyDictionary<Guid, Guid> LegacyShownTabs => legacyTabs;
    /// What the device store has adopted from an installed release.
    private readonly HashSet<DeviceAdoption> adopted = [];
    internal HashSet<DeviceAdoption> Adopted => adopted;
    /// The tab groups of the persistent session whose folders follow them.
    private readonly List<TabGroupRecord> keptTabGroups = [];
    private Guid? persistentWorkspace;
    internal Guid? PersistentWorkspace => persistentWorkspace;
    private long lastUse;
    internal long LastUse { get => lastUse; set => lastUse = value; }

    #endregion

    #region Constructors

    /// A device of `platform` whose saved windows and choices `storage` keeps,
    /// starting from `records`; without storage everything lives in memory.
    /// Each session it shows consults `access`. `requestTurn` asks the host
    /// for a drain on its next turn, and `closeBorrower` closes a borrowed
    /// workspace whose owner no longer lends its Space.
    public Device(DevicePlatform platform, SessionStorage? storage, DeviceRecords records, SpaceAccessAuthority access,
        Action<Change> announce, Action requestTurn, Action<Guid> closeBorrower, IClock clock) {
        ArgumentNullException.ThrowIfNull(platform);
        ArgumentNullException.ThrowIfNull(clock);
        ArgumentNullException.ThrowIfNull(records);
        ArgumentNullException.ThrowIfNull(access);
        ArgumentNullException.ThrowIfNull(announce);
        ArgumentNullException.ThrowIfNull(requestTurn);
        ArgumentNullException.ThrowIfNull(closeBorrower);
        this.platform = platform;
        this.storage = storage;
        this.access = access;
        this.announce = announce;
        this.requestTurn = requestTurn;
        this.closeBorrower = closeBorrower;
        this.clock = clock;
        foreach (var record in records.Windows) saved[record.Id] = record;
        reopening.AddRange(records.Reopening.Distinct());
        lastUse = records.Windows.Count == 0 ? 0 : records.Windows.Max(record => record.Used);
        keptPermissions.Restore(records.SitePermissions);
        keptEngines.Restore(records.SiteEngines);
        defaultEngine = records.DefaultEngine;
        shortcuts = records.Shortcuts;
        links = records.Links;
        agents = records.Agents;
        keptSetupDraft = platform.KeepsSetupDraft ? records.SetupDraft : null;
        setupCompleted = records.SetupCompleted;
        adopted.UnionWith(records.Adopted);
        keptTabGroups.AddRange(records.TabGroups);
        paletteMemories = records.PaletteMemories.ToImmutableDictionary();
        searchCatalog = records.SearchCatalog;
    }

    #endregion

    #region Actions - Workspaces

    /// Attaches a session a window may show as the workspace `workspaceId`,
    /// which the core drew for it, and publishes it whole. The session's
    /// Spaces answer to the device's grants from then on.
    public void Attach(NativeSessionAuthority authority, Guid workspaceId) {
        ArgumentNullException.ThrowIfNull(authority);
        lock (gate) {
            if (workspaces.Values.Any(attached => ReferenceEquals(attached, authority)) || !workspaces.TryAdd(workspaceId, authority))
                throw new InvalidOperationException("A session joins the device once, as a workspace of its own.");
        }
        authority.AttachAccess(access);
        authority.AttachDevice(this, workspaceId);
        announce(new WorkspaceOpened(workspaceId, authority.Kind, authority.Current));
    }

    /// Attaches the persistent session the core loaded, which every saved
    /// window shows, with the selection an older release kept in it.
    public void AttachPersistent(NativeSessionAuthority authority, JsonObject? legacySelection, Guid workspaceId) {
        Attach(authority, workspaceId);
        lock (gate) {
            persistentWorkspace = workspaceId;
            legacyTabs = LegacyTabs(legacySelection);
        }
    }

    /// The workspace `authority` is attached as, or null when it is not.
    public Guid? Identity(NativeSessionAuthority authority) {
        lock (gate) return workspaces.FirstOrDefault(entry => ReferenceEquals(entry.Value, authority)) is { Value: not null } known
            ? known.Key : null;
    }

    /// The workspaces that borrow a Space from `owner`.
    public IReadOnlyList<Guid> Borrowers(NativeSessionAuthority owner) {
        lock (gate) return [.. workspaces.Where(entry => entry.Value.Borrows(owner)).Select(entry => entry.Key)];
    }

    /// A workspace that closed takes the windows over it with it, each
    /// published as closed, then publishes that it closed. Their saved records
    /// stay, so a later launch restores those windows: a workspace closing is
    /// not the person closing its windows.
    public void Detach(Guid workspaceId) {
        Window[] closed;
        lock (gate) {
            if (!workspaces.Remove(workspaceId)) return;
            closed = [.. open.Values.Where(window => window.WorkspaceId == workspaceId)];
            foreach (var window in closed) open.Remove(window.Id);
        }
        foreach (var window in closed) announce(new WindowClosed(window.Id));
        announce(new WorkspaceClosed(workspaceId));
    }

    /// The app's preferences, which the persistent session keeps for every
    /// workspace: null before that session is attached, or while it keeps none.
    public AppPreferences? PersistentPreferences() {
        NativeSessionAuthority? persistent;
        lock (gate) persistent = persistentWorkspace is { } id ? workspaces.GetValueOrDefault(id) : null;
        return persistent?.Current.AppPreferences;
    }

    private static Dictionary<Guid, Guid> LegacyTabs(JsonObject? selection) {
        var tabs = new Dictionary<Guid, Guid>();
        foreach (var space in selection?[StoredSessionCodec.Key.Spaces] as JsonArray ?? []) {
            if (space is not JsonObject value) continue;
            try {
                tabs.TryAdd(StoredSessionCodec.Identity(value[StoredSessionCodec.Key.Id]),
                    StoredSessionCodec.Identity(value[StoredSessionCodec.Key.LegacySelectedTab]));
            } catch (Exception error) when (StoredSession.IsUndecodable(error)) {
                // A Space the older release stored without a readable tab adopts nothing.
            }
        }
        return tabs;
    }

    #endregion

    #region Actions - Session changes

    /// A command a window issued is about to read what that window shows.
    /// Answers a copy, or null for a window that is not open over `workspaceId`.
    public Window? Snapshot(Guid workspaceId, Guid? windowId) {
        if (windowId is not { } id) return null;
        lock (gate) return open.TryGetValue(id, out var window) && window.WorkspaceId == workspaceId ? window.Snapshot() : null;
    }

    /// The tabs the windows over `workspaceId` show, and those every saved
    /// window's record shows for the persistent session, which cleanup keeps.
    public IReadOnlySet<Guid> ShownTabs(Guid workspaceId) {
        lock (gate) {
            var shown = open.Values.Where(window => window.WorkspaceId == workspaceId)
                .SelectMany(window => window.ShownTabs).Select(tab => tab.TabId).OfType<Guid>().ToHashSet();
            if (workspaceId == persistentWorkspace)
                shown.UnionWith(saved.Values.SelectMany(record => record.Tabs).Select(tab => tab.TabId).OfType<Guid>());
            return shown;
        }
    }

    /// A workspace accepted `next` in place of `previous`: what the session
    /// changed is published first, then what the command did that the states
    /// cannot tell, then each window that shows something else. The window
    /// that issued the command takes what it chose to show, and every window
    /// over the workspace is repaired against `next`. Called with no session
    /// lock held.
    public void SessionPublished(Guid workspaceId, SessionState previous, SessionState next, WindowFollowUp? followUp,
        SessionTabEvents events) {
        ArgumentNullException.ThrowIfNull(previous);
        ArgumentNullException.ThrowIfNull(next);
        ArgumentNullException.ThrowIfNull(events);
        var changes = new List<Change>(SessionChanges.Publish(workspaceId, previous, next));
        changes.AddRange(events.Changes(workspaceId));
        NativeSessionAuthority? owner;
        lock (gate) {
            changes.AddRange(Changing(open.Values.Where(window => window.WorkspaceId == workspaceId), window => {
                if (followUp is not null && window.Id == followUp.Window?.Id) window.Apply(followUp);
                window.Repair(next);
            }, next));
            if (FollowingSpaces(workspaceId, next) is { } setup) changes.Add(setup);
            owner = workspaces.GetValueOrDefault(workspaceId);
        }
        foreach (var change in changes) announce(change);
        RememberPublished(workspaceId, previous, next);
        if (owner is not null) FollowOwner(owner);
    }

    /// Each workspace that borrows a Space from `owner` follows what `owner`
    /// accepted: its Space takes the owner's settings, published as its own
    /// change, and a workspace whose owner no longer lends its Space closes.
    /// Called with no lock held.
    private void FollowOwner(NativeSessionAuthority owner) {
        foreach (var borrowerId in Borrowers(owner)) {
            if (Attached(borrowerId) is not { } borrower) continue;
            if (borrower.LostSource()) closeBorrower(borrowerId);
            else if (borrower.FollowOwner() is { } followed)
                SessionPublished(borrowerId, followed.Previous, followed.Next, followUp: null, SessionTabEvents.None);
        }
    }

    /// Publishes a change a workspace's session started itself, such as a
    /// finished sync stage. Called with no lock held.
    public void Announce(Change change) {
        ArgumentNullException.ThrowIfNull(change);
        announce(change);
    }

    /// A workspace's session queued work that follows the host's turn. Called
    /// with no lock held.
    public void RequestTurn() => requestTurn();

    /// The host finished a turn: each workspace's session hears it.
    public void TurnEnded() {
        NativeSessionAuthority[] sessions;
        lock (gate) sessions = [.. workspaces.Values];
        foreach (var session in sessions) session.TurnEnded();
    }

    /// Runs `edit` on each of `windows` and answers a change for every one
    /// that shows something else over `session` afterwards, keeping saved
    /// records current. The caller holds the device lock.
    internal List<Change> Changing(IEnumerable<Window> windows, Action<Window> edit, SessionState session) {
        var changes = new List<Change>();
        foreach (var window in windows.ToArray()) {
            edit(window);
            if (Publishing(window, session) is { } change) changes.Add(change);
        }
        return changes;
    }

    /// What `window` shows over `session`, when it differs from what the
    /// device last published for it, keeping a saved window's record current
    /// with what it chose to show. The caller holds the device lock.
    internal WindowChanged? Publishing(Window window, SessionState session) {
        var state = window.State(session, workspaces.GetValueOrDefault(window.WorkspaceId)?.Kind.IsPrivate == true);
        published.TryGetValue(window.Id, out var before);
        if (state == before) return null;
        published[window.Id] = state;
        if (window.Saved && (before is null || before.ShownSpaceId != state.ShownSpaceId || !before.ShownTabs.SequenceEqual(state.ShownTabs)
            || !before.SplitColumnShares.SequenceEqual(state.SplitColumnShares))) Record(window);
        return new(state);
    }

    #endregion

    #region Actions - Records

    /// Keeps a saved window's record current and marks it most recently
    /// used, forgetting the least recently used records beyond the cap.
    private void Record(Window window) {
        saved[window.Id] = window.Record(++lastUse);
        Forget();
        storage?.EnqueueDevice(Records());
    }

    /// The tab groups of the persistent session whose folders follow them, as
    /// the device store keeps them.
    internal IReadOnlyList<TabGroupRecord> KeptTabGroups() {
        lock (gate) return [.. keptTabGroups];
    }

    /// Keeps `groups` as the tab groups whose folders follow them, saved when
    /// they changed.
    internal void KeepTabGroups(IReadOnlyList<TabGroupRecord> groups) {
        lock (gate) {
            if (keptTabGroups.SequenceEqual(groups)) return;
            keptTabGroups.Clear();
            keptTabGroups.AddRange(groups);
            storage?.EnqueueDevice(Records());
        }
    }

    private void Forget() {
        while (saved.Count > MaximumSavedWindows) saved.Remove(saved.Values.MinBy(record => record.Used)!.Id);
    }

    /// Everything the device store keeps, as it stands. The caller holds the device lock.
    internal DeviceRecords Records() => new([.. saved.Values.OrderBy(record => record.Used)], [.. reopening],
        [.. keptPermissions.PersistentRecords], [.. keptEngines.Choices], shortcuts, links, keptSetupDraft, setupCompleted,
        new HashSet<DeviceAdoption>(adopted), [.. keptTabGroups], defaultEngine) {
        PaletteMemories = paletteMemories,
        SearchCatalog = searchCatalog,
        Agents = agents
    };

    #endregion

    #region Actions - Adoptions

    /// Whether the device store carried `adoption` from an installed release.
    public bool HasAdopted(DeviceAdoption adoption) {
        lock (gate) return adopted.Contains(adoption);
    }

    /// Notes `adoption`, which a component saved with its marker in its own
    /// transaction, so every later write of the device records keeps it.
    public void NoteAdopted(DeviceAdoption adoption) {
        lock (gate) adopted.Add(adoption);
    }

    #endregion
}
