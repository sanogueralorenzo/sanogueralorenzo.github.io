using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// What one page intent or engine report needs: where it publishes what it
/// changed, and where it hands the engine commands it causes, which reach
/// their engines once the core lets go of its lock.
internal sealed record PageTurn(ChangeFeed Changes, Action<Engine, EngineCommand> Issue, ClosePreparations Closing);

#endregion

/// The pages this device hosts: which tab or transient request owns each, the
/// window that hosts it, the engine that hosts it and the live state its
/// engine reports. Never saved or synced. The platform decides when a page
/// opens or goes; the core decides whether it may, and on which engine, and
/// asks the engine to create, load and close it. A page that asks to close
/// itself, and one its engine closes on its own authority, close what owns
/// them as the core decides (see `CloseOwner`). A page another page opened
/// runs on its opener's engine, whatever the site's choice: every window,
/// popup, new tab, Peek or split a page opens stays in the engine that page
/// runs in. Any other page opens on the engine chosen for the site its tab
/// shows, when that engine is registered, and on the default engine
/// otherwise. A page moves to another engine when the person asks, when the
/// person asks for an address of a site chosen for another engine, when a
/// page no other page opened heads to such a site, or when the person accepts
/// an offer to try protected media on another engine. A requested move first
/// lets the current document refuse leaving through beforeunload.
///
/// A window hosts one page for a tab. The Mac's windows over one workspace
/// share one runtime store, so a second window shows the page the first opened
/// and never opens its own; each iPad scene keeps pages of its own, so two
/// scenes showing one tab each host a page for it.
///
/// Each page intent and engine report carries its own logic, which reads and
/// changes the pages through the state and rules kept here. A page's report
/// is stamped with the core's `clock`, and a visit it records takes its
/// identity from `ids`.
internal sealed class Pages(Device device, Engines engines, IClock clock, IIdSource ids) {
    #region Static Variables

    /// The most restore states the core holds; past it, the oldest goes.
    private const int MaximumRestoreStates = 64;

    #endregion

    #region Variables

    private readonly Dictionary<Guid, Page> open = [];

    /// What each Quick Window or Peek page its owner unloaded showed last, by
    /// page, so its window can still keep or archive it. A page is remembered
    /// until the session keeps or archives it, its owner releases it for good
    /// or its workspace closes, so the list holds no more than the transient
    /// windows still open.
    private readonly Dictionary<Guid, TransientPage> unloaded = [];
    /// What each tab's last page kept when it closed keeping its state, which
    /// the tab's next page restores. Memory only, never saved or synced; a tab
    /// that closes, is archived or loses its Space loses it.
    private readonly Dictionary<(Guid WorkspaceId, Guid TabId), (Guid SpaceId, EngineKind Engine, PageRestoreState State)> restoreStates = [];
    /// The pages asked to close keeping their state, until their engine says
    /// they are gone.
    private readonly Dictionary<Guid, (Engine Engine, Guid WorkspaceId, Guid SpaceId, Guid TabId)> keeping = [];
    private readonly List<(Guid WorkspaceId, Guid TabId)> restoreOrder = [];
    /// The history each tab's last page held when it closed keeping its
    /// state, which the tab's next page takes on, with the page that held it,
    /// whose engines may still hand back what they kept, or an empty identity
    /// for one the tab's archive brought back across a relaunch. Gone with
    /// the tab, its Space or its workspace, as what the tab kept is.
    private readonly Dictionary<(Guid WorkspaceId, Guid TabId), (Guid SpaceId, Guid PageId, PageHistory History)> histories = [];
    private readonly List<(Guid WorkspaceId, Guid TabId)> historyOrder = [];
    /// The tab groups extensions made of the pages, by identity, each shown as
    /// the folder of the same identity, starting from those of the persistent
    /// session the device store kept; see `PageGroup`.
    private readonly Dictionary<Guid, PageGroup> groups =
        device.KeptTabGroups().ToDictionary(record => record.Id, record => new PageGroup(record));

    /// The device whose workspaces and windows the pages belong to, and whose
    /// site choices pick their engines.
    internal Device Device => device;

    /// The engines pages open on.
    internal Engines Engines => engines;

    /// The core's clock, which stamps what a page records.
    internal IClock Clock => clock;

    /// Where what a page records takes its identity.
    internal IIdSource Ids => ids;

    /// Every page the core hosts.
    public IReadOnlyCollection<Page> All => open.Values;

    /// The engines a page is open on.
    public IReadOnlySet<EngineKind> HostingEngines => open.Values.Select(page => page.Engine.Kind).ToHashSet();

    /// Whether the engine new pages open on shows internal pages, such as an
    /// engine's settings.
    public bool OpensInternalPages => engines.Default?.Supports(EngineCapability.InternalPages) == true;

    #endregion

    #region Actions - Messages

    /// Runs one page intent, which publishes what it changed to the turn's
    /// `Changes` and hands the engine commands it causes to its `Issue`.
    public void Handle(PageIntent intent, PageTurn turn) => intent.Apply(this, turn);

    /// Applies what `engine` saw happen to one of its pages. A report about a
    /// page the core no longer knows, one another engine hosts, or one that
    /// would move a page backwards changes nothing. What the engine shows, a
    /// failure and a commit that ends it change the page's live state, which
    /// is published only when it differs. A finished navigation is recorded
    /// once per document in the Space the page lives in, and an icon reported
    /// for a recorded document goes to the page's tab; either waits while a
    /// transaction holds the workspace's session. A page whose renderer
    /// stopped comes back by the core's crash recovery.
    public void Report(PageEvent report, Engine engine, PageTurn turn) => report.Apply(this, engine, turn);

    #endregion

    #region Actions - Engines

    /// Moves the page to the entry `entryId` names in its history. Its engine
    /// goes to an entry it holds itself. An entry another engine held takes
    /// the page back to that engine, once the page's before-unload decision
    /// allows it. An entry of the page's own engine that it no longer holds
    /// loads afresh there, as itself. A page its engine does not hold yet
    /// goes nowhere.
    internal void Traverse(Page page, Guid entryId, PageTurn turn) {
        if (page.Phase != PagePhase.Live) return;
        if (page.History.Holds(entryId)) {
            page.History.Go(entryId);
            turn.Issue(page.Engine, new GoToHistoryEntry(page.Id, entryId));
        } else if (page.History.Returns(entryId)) {
            turn.Closing.Return(page, entryId, turn);
        } else if (page.History.Reaches(entryId)) {
            LoadAfresh(page, entryId, turn);
        }
    }

    /// Loads the entry `entryId` names afresh on the page's own engine.
    private void LoadAfresh(Page page, Guid entryId, PageTurn turn) {
        PageHistoryEntry? entry = null;
        Update(page, turn.Changes, () => entry = page.History.Load(entryId));
        turn.Issue(page.Engine, new LoadPage(page.Id, entry!.Url, entry.Id));
    }

    /// Takes the page back to the engine that held the entry `entryId` names.
    /// Its engine closes it, keeping its history for the run the page leaves,
    /// and the entry's engine creates it again, restoring the history it kept
    /// and going to the entry, or loading the entry afresh when it kept none.
    /// An entry whose engine this device no longer registers loads afresh on
    /// the page's own engine.
    internal void Return(Page page, Guid entryId, PageTurn turn) {
        if (page.History.Entry(entryId) is not { } entry) return;
        if (engines.Registered(page.History.EngineOf(entryId)!) is not { } engine) {
            LoadAfresh(page, entryId, turn);
            return;
        }
        var (_, restore, load) = page.History.Return(entryId);
        if (page.Phase.HoldsEnginePage) turn.Issue(page.Engine, new ClosePage(page.Id, KeepsState: true));
        Update(page, turn.Changes, () => page.Return(engine, restore?.Url ?? entry.Url, load?.Id));
        turn.Issue(engine, new CreatePage(page.Id, page.ProfileId, device.Workspace(page.WorkspaceId).IsPrivateBrowsing,
            page.WindowId, restore));
    }

    /// Closes the page on its engine, which hands back its history for the
    /// run the page leaves, and creates it on `engine`, which loads `address`
    /// once it has created it, then publishes the move and why it happened.
    internal void Rehost(Page page, Engine engine, string? address, RehostReason reason, PageTurn turn) {
        var from = page.Engine;
        if (page.Phase.HoldsEnginePage) turn.Issue(from, new ClosePage(page.Id, KeepsState: true));
        Update(page, turn.Changes, () => page.Rehost(engine, address, reason));
        turn.Issue(engine, new CreatePage(page.Id, page.ProfileId, device.Workspace(page.WorkspaceId).IsPrivateBrowsing, page.WindowId,
            RestoreState: null));
        turn.Changes.Publish(new PageRehosted(page.Id, page.SpaceId, address is null ? null : new WebAddress(address).Origin, from.Kind,
            engine.Kind, reason));
    }

    /// The engine a new page in `space` opens on: its opener's, when another
    /// page opened it, so a page never leaves the engine of the page that
    /// opened it; otherwise the registered engine chosen for the site `tab`
    /// shows, or the default engine. Null when no engine is the default.
    internal Engine? Opening(SpaceState space, TabState? tab, Page? opener) =>
        opener?.Engine ?? Chosen(space, tab) ?? engines.Default;

    /// The page `pageId` names as the opener of a new page in `space` of
    /// `workspaceId`: one the core hosts in that workspace and the Space's
    /// profile. Null for none, or for one the core no longer hosts, which
    /// leaves the new page to the site's choice.
    internal Page? Opener(Guid? pageId, Guid workspaceId, SpaceState space) =>
        pageId is { } id && Hosted(id) is { } opener && opener.WorkspaceId == workspaceId && opener.ProfileId == space.ProfileId
            ? opener
            : null;

    /// The registered engine chosen for the site `tab` shows, or null when
    /// none is, or for a page without a tab, which opens before it has an
    /// address.
    internal Engine? Chosen(SpaceState space, TabState? tab) => tab?.Url is { } url ? Chosen(space, url) : null;

    /// The registered engine chosen in `space` for the site `url` belongs to,
    /// or null when none is.
    internal Engine? Chosen(SpaceState space, string url) =>
        new WebAddress(url).Origin is { } origin && device.ChosenEngine(space.Id, origin) is { } kind ? engines.Registered(kind) : null;

    #endregion

    #region Actions - Workspaces

    /// A workspace closed: each of its pages is gone at once, and its engine
    /// closes what it still holds afterwards, keeping nothing. What its Quick
    /// Window or Peek pages showed when their owners unloaded them is
    /// forgotten too.
    public void Drop(Guid workspaceId, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        ArgumentNullException.ThrowIfNull(changes);
        ArgumentNullException.ThrowIfNull(issue);
        foreach (var page in open.Values.Where(page => page.WorkspaceId == workspaceId).ToArray()) {
            open.Remove(page.Id);
            changes.Publish(new PageRemoved(page.Id));
            if (page.Phase.HoldsEnginePage) issue(page.Engine, new ClosePage(page.Id, KeepsState: false));
        }
        foreach (var remembered in unloaded.Values.Where(remembered => remembered.WorkspaceId == workspaceId).ToArray())
            unloaded.Remove(remembered.Id);
        foreach (var key in restoreStates.Keys.Where(key => key.WorkspaceId == workspaceId).ToArray()) Forget(key);
        foreach (var key in histories.Keys.Where(key => key.WorkspaceId == workspaceId).ToArray()) ForgetHistory(key);
        foreach (var group in groups.Values.Where(group => group.WorkspaceId == workspaceId).ToArray()) {
            if (group.Persists) group.Detach();
            else groups.Remove(group.Id);
        }
    }

    #endregion

    #region Actions - Owners

    /// Closes what owns `page`, as the person closing it would. Its tab closes
    /// the way its section closes one (see `CloseTab`), and the window that
    /// hosts the page returns to the tab it showed before; whatever shows a
    /// Quick Window's or Peek's page closes, keeping nothing of it. A tab its
    /// Space no longer holds and a Space being deleted have nothing to close,
    /// and a locked Space, or the Start Page as its Space's only tab, keeps
    /// its tab.
    internal void CloseOwner(Page page, PageTurn turn) {
        if (device.Attached(page.WorkspaceId) is not { } workspace) return;
        if (page.TabId is null) {
            if (!workspace.IsDeleting(page.SpaceId) && workspace.Current.Space(page.SpaceId) is not null)
                turn.Changes.Publish(new TransientPageClosed(page.Id, page.WorkspaceId));
            return;
        }
        if (Tab(page) is not { } tab) return;
        try {
            workspace.Handle(new CloseTab(page.WorkspaceId, page.WindowId, page.SpaceId, tab.Id), clock.Now, ids, this);
        } catch (Rejected) {
            // The Space is locked, or its only tab is the Start Page.
        }
    }

    #endregion

    #region Actions - Queries

    /// The live state of the page that shows `tabId` of a workspace in
    /// `windowId`, or in another window of the workspace when that window
    /// hosts none, or null when no page shows the tab.
    public PageLiveState? Showing(Guid workspaceId, Guid windowId, Guid tabId) {
        PageLiveState? elsewhere = null;
        foreach (var page in open.Values) {
            if (page.WorkspaceId != workspaceId || page.TabId != tabId || !page.Phase.HoldsEnginePage) continue;
            if (page.WindowId == windowId) return page.Live;
            elsewhere ??= page.Live;
        }
        return elsewhere;
    }

    #endregion

    #region Actions - Reports

    /// Brings back each page whose renderer stopped while nobody saw it and
    /// that a window now shows, or shows its failure once the recovery budget
    /// is spent.
    public void RecoverShown(ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        ArgumentNullException.ThrowIfNull(changes);
        ArgumentNullException.ThrowIfNull(issue);
        foreach (var page in open.Values.Where(page => page.RecoversWhenShown && page.Phase == PagePhase.Live && IsShown(page))) {
            var recovers = false;
            Update(page, changes, () => recovers = page.Recover());
            if (recovers) issue(page.Engine, new RecoverPage(page.Id));
        }
    }

    /// Whether a window shows the page: a Quick Window's or Peek's page always,
    /// a tab's page when a window over its workspace shows the tab or a split
    /// it belongs to.
    internal bool IsShown(Page page) => page.TabId is not { } tabId || device.Shows(page.WorkspaceId, page.SpaceId, tabId);

    /// Applies `update` to the page, and publishes the page when that changed
    /// what readers see of it.
    internal void Update(Page page, ChangeFeed changes, Action update) {
        var before = page.State;
        update();
        if (page.State != before) changes.Publish(new PageChanged(page.State));
    }

    internal void Enter(Page page, PagePhase next, ChangeFeed changes) {
        if (page.Enter(next)) changes.Publish(new PageChanged(page.State));
    }

    /// Applies a page's edit to the session of the workspace it lives in; a
    /// workspace that is gone takes nothing.
    internal void Edit(Page page, PageEdit edit, ChangeFeed changes) {
        if (device.Attached(page.WorkspaceId) is not { } workspace) return;
        foreach (var change in workspace.Apply(edit)) changes.Publish(change);
    }

    #endregion

    #region Actions - Residency

    /// Stamps each tab's page with whether a window shows it now, and ends the
    /// Picture in Picture of every page that may not keep one, which `issue`
    /// asks its engine for; see `EndPictureInPicture`.
    public void Stamp(DateTimeOffset now, Action<Engine, EngineCommand> issue) {
        ArgumentNullException.ThrowIfNull(issue);
        var shown = new Dictionary<Guid, IReadOnlySet<Guid>>();
        foreach (var page in open.Values) {
            var shownAgain = false;
            if (page.TabId is { } tabId) {
                if (!shown.TryGetValue(page.WorkspaceId, out var tabs)) shown[page.WorkspaceId] = tabs = device.OnScreenTabs(page.WorkspaceId);
                shownAgain = page.Seen(tabs.Contains(tabId), now);
            }
            EndPictureInPicture(page, shownAgain, issue);
        }
    }

    /// Asks the page's engine to end the page's Picture in Picture, returning
    /// its video to its place in the page, when a window shows the page again
    /// (`shownAgain`), however the person came back to it and whether the
    /// video left automatically or at their request. It asks whenever this
    /// process may not show the page's Space too: a locked Space, one being
    /// deleted or one that is gone keeps no video on screen, whether a tab, a
    /// Quick Window or a Peek owns the page, so one that floats while its
    /// Space is locked is asked to end each time the core looks.
    internal void EndPictureInPicture(Page page, bool shownAgain, Action<Engine, EngineCommand> issue) {
        if (page.ShowsPictureInPicture && (shownAgain || Shown(page) is null)) issue(page.Engine, new ExitPictureInPicture(page.Id));
    }

    /// The tabs of `workspaceId` whose pages run media, which stay open and
    /// loaded however long nobody looks at them.
    internal IReadOnlySet<Guid> TabsRunningMedia(Guid workspaceId) =>
        open.Values.Where(page => page.WorkspaceId == workspaceId && page.RunsMedia).Select(page => page.TabId).OfType<Guid>()
            .ToHashSet();

    /// Forgets what a tab kept once the tab is gone from its Space, closed or
    /// archived, or its Space is gone or being deleted.
    public void PruneRestoreStates() {
        foreach (var (key, kept) in restoreStates.ToArray())
            if (Held(key.WorkspaceId, kept.SpaceId, key.TabId) is null) Forget(key);
        foreach (var (key, kept) in histories.ToArray())
            if (Held(key.WorkspaceId, kept.SpaceId, key.TabId) is null) ForgetHistory(key);
    }

    /// Asks the engine to close the page. A tab's page closed keeping its
    /// state hands back what brings it back, which the tab keeps.
    internal void Close(Page page, bool keepsState, Action<Engine, EngineCommand> issue) {
        if (keepsState && page.TabId is { } tabId) {
            keeping[page.Id] = (page.Engine, page.WorkspaceId, page.SpaceId, tabId);
            page.History.Release();
            KeepHistory((page.WorkspaceId, tabId), page);
        }
        issue(page.Engine, new ClosePage(page.Id, keepsState));
    }

    /// The page `pageId` names closed on `engine`, handing back `state`. When
    /// the core asked that engine to close it keeping its state, its tab
    /// keeps what it handed back for the tab's next page.
    internal void KeepRestoreState(Guid pageId, Engine engine, PageRestoreState? state) {
        if (keeping.Remove(pageId, out var kept) && ReferenceEquals(kept.Engine, engine) && state is { } restoreState)
            Keep((kept.WorkspaceId, kept.TabId), kept.SpaceId, engine.Kind, restoreState);
        // A page that left `engine` for another keeps what it handed back for
        // the stretch of its history that engine held.
        if (Hosted(pageId) is { } page && !ReferenceEquals(page.Engine, engine)) page.History.Keep(engine.Kind, state);
        else if (histories.Values.FirstOrDefault(kept => kept.PageId == pageId).History is { } history) history.Keep(engine.Kind, state);
    }

    /// What the tab kept for its next page, taken once, when the tab still
    /// shows the address it kept and the page opens on the engine that kept
    /// it. What it kept for another address or engine is dropped.
    internal PageRestoreState? Restorable(Guid workspaceId, SpaceState space, Guid tabId, EngineKind engine) {
        var key = (workspaceId, tabId);
        if (!restoreStates.TryGetValue(key, out var kept)) return null;
        Forget(key);
        var tab = space.Tabs.FirstOrDefault(tab => tab.Id == tabId);
        return kept.SpaceId == space.Id && kept.Engine == engine && tab?.Url is { } url
            && new WebAddress(url).IsSamePage(new WebAddress(kept.State.Url)) ? kept.State : null;
    }

    /// The history the tab's last page held, taken once, when the tab still
    /// lives in the Space that page did and shows the entry the history
    /// shows. A history for another Space or address is dropped.
    /// Answers whether it came from the tab's archive, whose engine history
    /// the platform restores itself.
    internal (PageHistory History, bool Archived)? KeptHistory(Guid workspaceId, SpaceState space, Guid tabId) {
        var key = (workspaceId, tabId);
        if (!histories.TryGetValue(key, out var kept)) return null;
        ForgetHistory(key);
        var tab = space.Tabs.FirstOrDefault(tab => tab.Id == tabId);
        return kept.SpaceId == space.Id && kept.History.Shown is { } shown && tab?.Url is { } url
            && new WebAddress(url).IsSamePage(new WebAddress(shown.Url))
                ? (kept.History, kept.PageId == Guid.Empty)
                : null;
    }

    /// The tab `tabId` of `space` takes on `history`, which its archive kept
    /// across a relaunch, for its next page. A tab that has a page, or holds
    /// a history it kept since, keeps that instead.
    internal void KeepArchivedHistory(Guid workspaceId, SpaceState space, Guid tabId, PageHistory history) {
        var key = (workspaceId, tabId);
        if (histories.ContainsKey(key) || open.Values.Any(page => page.WorkspaceId == workspaceId && page.TabId == tabId)) return;
        Remember(key, (space.Id, Guid.Empty, history));
    }

    /// The history of the page `pageId` names, or of the tab's page it was
    /// until it closed keeping its state, as its tab's archive keeps it. None
    /// for a page of a private workspace, open or closed.
    internal byte[]? ArchivedHistory(Guid pageId) {
        var (workspaceId, history) = Hosted(pageId) is { } page ? (page.WorkspaceId, page.History)
            : histories.FirstOrDefault(kept => kept.Value.PageId == pageId) is { Value.History: { } closed } kept
                ? (kept.Key.WorkspaceId, closed)
                : (Guid.Empty, null);
        return history is not null && device.Attached(workspaceId) is { IsPrivateBrowsing: false } ? history.Archive() : null;
    }

    private void KeepHistory((Guid WorkspaceId, Guid TabId) key, Page page) {
        ForgetHistory(key);
        if (page.History.Shown is not null) Remember(key, (page.SpaceId, page.Id, page.History));
    }

    private void Remember((Guid WorkspaceId, Guid TabId) key, (Guid SpaceId, Guid PageId, PageHistory History) kept) {
        histories[key] = kept;
        historyOrder.Add(key);
        while (historyOrder.Count > MaximumRestoreStates) ForgetHistory(historyOrder[0]);
    }

    private void ForgetHistory((Guid WorkspaceId, Guid TabId) key) {
        histories.Remove(key);
        historyOrder.Remove(key);
    }

    private void Keep((Guid WorkspaceId, Guid TabId) key, Guid spaceId, EngineKind engine, PageRestoreState state) {
        Forget(key);
        restoreStates[key] = (spaceId, engine, state);
        restoreOrder.Add(key);
        while (restoreOrder.Count > MaximumRestoreStates) Forget(restoreOrder[0]);
    }

    private void Forget((Guid WorkspaceId, Guid TabId) key) {
        restoreStates.Remove(key);
        restoreOrder.Remove(key);
    }

    /// The tab a page belongs to, as its Space holds it now.
    internal TabState? Tab(Page page) => page.TabId is { } tabId ? Held(page.WorkspaceId, page.SpaceId, tabId) : null;

    /// The Space a page lives in, while its workspace is attached, the Space
    /// is not being deleted and this process may show it; null otherwise.
    internal SpaceState? Shown(Page page) =>
        device.Attached(page.WorkspaceId) is { } workspace && !workspace.IsDeleting(page.SpaceId)
            && workspace.Current.Space(page.SpaceId) is { } space && !workspace.IsLocked(space)
            ? space : null;

    /// A tab its Space still holds, in a Space that is not being deleted.
    private TabState? Held(Guid workspaceId, Guid spaceId, Guid tabId) =>
        device.Attached(workspaceId) is { } workspace && !workspace.IsDeleting(spaceId)
            && workspace.Current.Space(spaceId) is { } space
            ? space.Tabs.FirstOrDefault(tab => tab.Id == tabId) : null;

    #endregion

    #region Actions - Tab groups

    /// The tab group `groupId` names while the core follows it, or null.
    internal PageGroup? Group(Guid groupId) => groups.GetValueOrDefault(groupId);

    /// The core follows `group` from now on.
    internal void Follow(PageGroup group) => groups[group.Id] = group;

    /// Asks the engines for what the folders that show their tab groups hold
    /// now, which `issue` hands them, stops following a group whose folder or
    /// Space went, and has the device store keep the persistent session's; see
    /// `PageGroup.Reconcile`.
    public void ReconcileGroups(Action<Engine, EngineCommand> issue) {
        ArgumentNullException.ThrowIfNull(issue);
        foreach (var group in groups.Values.ToArray())
            if (!group.Reconcile(this, issue)) groups.Remove(group.Id);
        device.KeepTabGroups([.. groups.Values.Select(group => group.Record()).OfType<TabGroupRecord>()]);
    }

    #endregion

    #region Actions - Rules

    /// The page `pageId` names while the core hosts it, or null.
    public Page? Hosted(Guid pageId) => open.GetValueOrDefault(pageId);

    /// Whether the core hosts the page `pageId` names.
    internal bool IsOpen(Guid pageId) => open.ContainsKey(pageId);

    /// Whether `page` goes when the window that hosts it closes. The windows
    /// over one workspace share its pages only where both the device and the
    /// workspace's kind let them; a page they share stays for the workspace's
    /// other windows, or its next.
    internal bool GoesWithItsWindow(Page page) => device.Attached(page.WorkspaceId) is not { } workspace
        || !(device.Platform.SharesPagesAcrossWindows && workspace.Kind.SharesPagesAcrossWindows);

    /// The core hosts `page` from now on.
    internal void Add(Page page) => open[page.Id] = page;

    /// The core no longer hosts the page `pageId` names, which it answers, or
    /// null when it hosted no such page.
    internal Page? Remove(Guid pageId) => open.Remove(pageId, out var page) ? page : null;

    /// The page `pageId` names, refused with `UnknownPage` when the core does
    /// not host it.
    internal Page Known(Guid pageId) => open.TryGetValue(pageId, out var page) ? page : throw new Rejected(new UnknownPage(pageId));

    /// The Quick Window or Peek page `pageId` names, as it is or as it was
    /// when its owner unloaded it, or null when this device hosts no such page
    /// and remembers none. An unloaded page cannot move to a tab's window, and
    /// one of a workspace that closed is not remembered.
    public TransientPage? Transient(Guid pageId) => open.TryGetValue(pageId, out var page)
        ? page.TabId is null ? Transient(page) : null
        : unloaded.GetValueOrDefault(pageId);

    /// Whether the core remembers what the Quick Window or Peek page `pageId`
    /// names showed when its owner unloaded it.
    internal bool RemembersUnloaded(Guid pageId) => unloaded.ContainsKey(pageId);

    /// Remembers what a Quick Window or Peek page showed when its owner
    /// unloaded it.
    internal void RememberUnloaded(TransientPage page) => unloaded[page.Id] = page;

    /// Forgets an unloaded Quick Window or Peek page the session kept or
    /// archived, or its owner released for good.
    public void ForgetUnloaded(Guid pageId) => unloaded.Remove(pageId);

    /// What a Quick Window's or Peek's page shows, as its window keeps or
    /// archives it.
    internal TransientPage Transient(Page page) => new(page.Id, page.WorkspaceId, page.SpaceId, page.ProfileId,
        page.Engine.Supports(EngineCapability.WorkspaceTransfer), page.Live.Address, page.Live.Title);

    /// The Space a page may live in: one the workspace holds, that is not
    /// being deleted, here or in the workspace a borrowed one borrows from, and
    /// that this process may show.
    internal SpaceState Hosting(NativeSessionAuthority workspace, Guid spaceId) {
        var space = workspace.Current.KnownSpace(spaceId);
        if (workspace.IsDeleting(spaceId)) throw new Rejected(new SpaceBeingDeleted(spaceId));
        if (workspace.IsLocked(space)) throw new Rejected(new SpaceLocked(spaceId));
        return space;
    }

    /// A window hosts one page for a tab at a time. Whether the workspace holds
    /// the tab is not checked yet: selection can present a tab before the
    /// core's session has it, and an `UnknownTab` rejection arrives with the
    /// session intents.
    internal void RequireUnowned(Guid workspaceId, Guid windowId, Guid? tabId, Page? moving) {
        if (tabId is not { } tab) return;
        if (open.Values.FirstOrDefault(page => page != moving && page.WorkspaceId == workspaceId && page.WindowId == windowId
            && page.TabId == tab) is { } owner)
            throw new Rejected(new TabAlreadyHasPage(tab, owner.Id));
    }

    #endregion
}
