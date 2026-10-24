using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The session change feed: every accepted state reaches a reader as the
/// changes that take it from the state before, derived by comparing the two,
/// so a reader that applies them by the rules each change documents holds the
/// core's state, and applying a batch twice changes nothing.
public sealed partial class BrowserContractsTests {
    /// Applies the session changes of one workspace the way a platform's read
    /// model does, by the rules each change record documents.
    private sealed class SessionReader(Guid workspace, SessionState opened) {
        public SessionState State { get; private set; } = opened;

        /// Each Space's sidebar lists, by section for a section's top level and by
        /// folder for a folder's inside.
        private readonly Dictionary<Guid, Dictionary<(TabPlacement?, Guid?), SidebarList>> sidebars =
            opened.Spaces.ToDictionary(space => space.Id, space => Keyed(space.Sidebar.Lists));

        /// A reader of the workspace a batch opens.
        public static SessionReader Opening(IEnumerable<Change> changes) {
            var opened = Assert.Single(changes.OfType<WorkspaceOpened>());
            return new(opened.WorkspaceId, opened.Session);
        }

        public void Apply(IEnumerable<Change> changes) {
            foreach (var change in changes) Apply(change);
        }

        private void Apply(Change change) {
            switch (change) {
                case WorkspaceOpened opened when opened.WorkspaceId == workspace:
                    State = opened.Session;
                    sidebars.Clear();
                    foreach (var space in opened.Session.Spaces) sidebars[space.Id] = Keyed(space.Sidebar.Lists);
                    break;
                case SpacesChanged spaces when spaces.WorkspaceId == workspace:
                    var kept = State.Spaces.Where(space => !spaces.Removed.Contains(space.Id)).ToList();
                    foreach (var added in spaces.Added) Upsert(kept, added, space => space.Id);
                    State = State with { Spaces = Ordered(kept, spaces.Order, space => space.Id) };
                    foreach (var id in spaces.Removed) sidebars.Remove(id);
                    foreach (var added in spaces.Added) sidebars[added.Id] = Keyed(added.Sidebar.Lists);
                    break;
                case SidebarChanged sidebar when sidebar.WorkspaceId == workspace:
                    var lists = sidebars[sidebar.SpaceId];
                    foreach (var id in sidebar.RemovedFolderIds) lists.Remove((null, id));
                    foreach (var list in sidebar.Lists) lists[Key(list)] = list;
                    break;
                case SpaceSettingsChanged settings when settings.WorkspaceId == workspace:
                    Edit(settings.SpaceId, space => space with { Settings = settings.Settings });
                    break;
                case TabsChanged tabs when tabs.WorkspaceId == workspace:
                    Edit(tabs.SpaceId, space => space with {
                        Tabs = Rows(space.Tabs, tabs.Updated, tabs.Removed, tabs.Order, tab => tab.Id, recordedFirst: false)
                    });
                    break;
                case FoldersChanged folders when folders.WorkspaceId == workspace:
                    Edit(folders.SpaceId, space => space with {
                        Folders = Rows(space.Folders, folders.Updated, folders.Removed, folders.Order, folder => folder.Id, recordedFirst: false)
                    });
                    break;
                case SplitGroupsChanged groups when groups.WorkspaceId == workspace:
                    Edit(groups.SpaceId, space => space with { SplitGroups = groups.Groups });
                    break;
                case ArchiveChanged archive when archive.WorkspaceId == workspace:
                    Edit(archive.SpaceId, space => space with {
                        ArchivedTabs = Rows(space.ArchivedTabs, archive.Archived, archive.Removed, archive.Order, archived => archived.Tab.Id,
                            recordedFirst: false)
                    });
                    break;
                case HistoryChanged history when history.WorkspaceId == workspace:
                    Edit(history.SpaceId, space => space with {
                        History = Rows(space.History, history.Recorded, history.Removed, history.Order, entry => entry.Id, recordedFirst: true)
                    });
                    break;
                case WorkspaceChanged changed when changed.WorkspaceId == workspace:
                    State = State with {
                        DefaultSpaceId = changed.DefaultSpaceId,
                        DisposableSeedMarker = changed.IsDisposableSeed ? State.DisposableSeedMarker ?? Guid.NewGuid() : null,
                        SpaceDeletions = changed.SpaceDeletions
                    };
                    break;
                case AppPreferencesChanged preferences when preferences.WorkspaceId == workspace:
                    State = State with { AppPreferences = preferences.Preferences };
                    break;
            }
        }

        /// Asserts that the sidebar lists the reader applied are the ones each Space
        /// of `state` resolves.
        public void AssertSidebars(SessionState state) {
            Assert.Equal(state.Spaces.Select(space => space.Id).Order(), sidebars.Keys.Order());
            foreach (var space in state.Spaces) {
                var expected = Keyed(space.Sidebar.Lists);
                var applied = sidebars[space.Id];
                Assert.Equal(expected.Keys.ToHashSet(), applied.Keys.ToHashSet());
                foreach (var (key, list) in expected) Assert.Equal(list, applied[key]);
            }
        }

        private static (TabPlacement?, Guid?) Key(SidebarList list) => list.FolderId is { } id ? (null, id) : (list.Section, null);

        private static Dictionary<(TabPlacement?, Guid?), SidebarList> Keyed(IEnumerable<SidebarList> lists) =>
            lists.ToDictionary(Key);

        private void Edit(Guid spaceId, Func<SpaceState, SpaceState> edit) =>
            State = State with { Spaces = [.. State.Spaces.Select(space => space.Id == spaceId ? edit(space) : space)] };

        private static IReadOnlyList<T> Rows<T>(IReadOnlyList<T> rows, IReadOnlyList<T> updated, IReadOnlyList<Guid> removed,
            IReadOnlyList<Guid>? order, Func<T, Guid> identity, bool recordedFirst) {
            var kept = rows.Where(row => !removed.Contains(identity(row))).ToList();
            if (recordedFirst) {
                var recorded = updated.Select(identity).ToHashSet();
                kept.RemoveAll(row => recorded.Contains(identity(row)));
                kept.InsertRange(0, updated);
            } else {
                foreach (var row in updated) Upsert(kept, row, identity);
            }
            return Ordered(kept, order, identity);
        }

        private static void Upsert<T>(List<T> rows, T row, Func<T, Guid> identity) {
            var index = rows.FindIndex(existing => identity(existing) == identity(row));
            if (index >= 0) rows[index] = row;
            else rows.Add(row);
        }

        private static IReadOnlyList<T> Ordered<T>(List<T> rows, IReadOnlyList<Guid>? order, Func<T, Guid> identity) {
            if (order is null) return rows;
            var byId = rows.ToDictionary(identity);
            Assert.Equal(byId.Count, order.Count);
            return [.. order.Select(id => byId[id])];
        }
    }

    private static NativeSessionAuthority MaximalSession() => TestWorkspaces.Session(MaximalDocument());

    /// The maximal stored-session fixture.
    private static JsonNode MaximalDocument() => JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Session",
        "Fixtures", "maximal-session.json")))!;

    /// Every command the recorded script runs, from the windows it names,
    /// reaches a reader that started from the opened workspace as changes
    /// that reproduce the core's state after each commit; applying each batch
    /// again changes nothing.
    [Fact]
    public void AReaderOfTheChangesHoldsTheCoresStateAfterEveryCommand() {
        var clock = new TestClock(DateTimeOffset.UnixEpoch);
        var ids = new TestIds();
        using var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Desktop), clock, ids);
        var engine = RecordedIntents.PageEngine(app);
        var opening = app.Send(new OpenWorkspace(WorkspaceKind.Persistent, TestWorkspaces.Seed(MaximalDocument())));
        var workspace = TestWorkspaces.Opened(opening);
        var authority = app.Workspace(workspace);
        var reader = SessionReader.Opening(opening);
        TestGrants.UnlockGuarded(app.Send, workspace, authority.Current);
        Assert.Equal(authority.Current, reader.State);
        var published = new HashSet<Type>();
        foreach (var step in JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Session", "Fixtures",
            "session-commands.json")))!["commands"]!.AsArray()) {
            var request = step!["request"]!.DeepClone().AsObject();
            Guid? window = null;
            if (step["window"] is { } shown) {
                window = Guid.NewGuid();
                reader.Apply(app.Send(new OpenWindow(window.Value, workspace, Saved: false, CopyingWindowId: null,
                    shown["spaceId"] is { } space ? Guid.Parse(space.GetValue<string>()) : null,
                    [.. shown["tabs"]!.AsArray().Select(tab => new ShownTab(Guid.Parse(tab!["spaceId"]!.GetValue<string>()),
                        tab["tabId"] is { } id ? Guid.Parse(id.GetValue<string>()) : null))],
                    RestoresTabs: true)));
                request["windowId"] = window.ToString();
            }
            IReadOnlyList<Change> changes;
            if (RecordedIntents.LaunchPlan(request, workspace) is { } plan) {
                app.Query(plan);
                changes = app.Drain();
            } else if (RecordedIntents.Typed(request, workspace, window, authority.Current) is { } intents) {
                clock.Now = RecordedIntents.Time(request);
                ids.Supply(RecordedIntents.Identities(request));
                changes = RecordedIntents.Send(app, engine, request, intents, window);
                var granted = new List<Change>();
                TestGrants.UnlockGuarded(intent => { var sent = app.Send(intent); granted.AddRange(sent); return sent; }, workspace,
                    authority.Current);
                changes = [.. changes, .. granted];
            } else if (RecordedIntents.Navigation(request) is { } navigation) {
                clock.Now = navigation.At;
                changes = RecordedIntents.Report(app, engine, navigation, workspace, window!.Value);
            } else {
                throw new InvalidOperationException($"{request["operation"]}: every recorded command is an intent or an engine report now.");
            }
            published.UnionWith(changes.Select(change => change.GetType()));
            reader.Apply(changes);
            Assert.Equal(authority.Current, reader.State);
            reader.AssertSidebars(authority.Current);
            reader.Apply(changes);
            Assert.Equal(authority.Current, reader.State);
            reader.AssertSidebars(authority.Current);
            if (window is { } opened) app.Send(new CloseWindow(opened));
        }
        Assert.Superset(new HashSet<Type> {
            typeof(SpacesChanged), typeof(SpaceSettingsChanged), typeof(TabsChanged), typeof(FoldersChanged),
            typeof(SplitGroupsChanged), typeof(HistoryChanged), typeof(ArchiveChanged), typeof(WorkspaceChanged),
            typeof(AppPreferencesChanged), typeof(TabCopied), typeof(SidebarChanged)
        }, published);
    }

    [Fact]
    public void AStateThatDidNotChangeAndSpacesAnEditKeptPublishNothing() {
        var authority = MaximalSession();
        var session = authority.Current;
        var workspace = Guid.NewGuid();
        Assert.Empty(SessionChanges.Publish(workspace, session, session));
        // Equal states that are other objects publish nothing either.
        Assert.Empty(SessionChanges.Publish(workspace, session, MaximalSession().Current));
        Assert.Empty(SessionChanges.Publish(workspace, session, session with { Spaces = [.. session.Spaces] }));

        var first = session.Spaces[0];
        var renamed = first with { Tabs = [first.Tabs[0] with { CustomTitle = "Renamed" }, .. first.Tabs.Skip(1)] };
        var tabs = Assert.IsType<TabsChanged>(Assert.Single(SessionChanges.Publish(workspace, session,
            session with { Spaces = [renamed, .. session.Spaces.Skip(1)] })));
        Assert.Equal((workspace, first.Id), (tabs.WorkspaceId, tabs.SpaceId));
        Assert.Equal([renamed.Tabs[0]], tabs.Updated);
        Assert.Empty(tabs.Removed);
        Assert.Null(tabs.Order);
    }

    [Fact]
    public void RecordsArriveByIdentityWithAnOrderOnlyWhenTheirPlacementDoesNotGiveIt() {
        var session = MaximalSession().Current;
        var workspace = Guid.NewGuid();
        var space = session.Spaces.First(space => space.History.Count > 1 && space.ArchivedTabs.Count > 1);
        IReadOnlyList<Change> Edited(SpaceState edited) =>
            SessionChanges.Publish(workspace, session, session with { Spaces = [.. session.Spaces.Select(item => item.Id == edited.Id ? edited : item)] });

        // A visit to an address the history holds moves its entry to the front.
        var visited = space.History[^1] with { Title = "Visited again", VisitCount = space.History[^1].VisitCount + 1 };
        var history = Assert.IsType<HistoryChanged>(Assert.Single(Edited(space with { History = [visited, .. space.History.SkipLast(1)] })));
        Assert.Equal([visited], history.Recorded);
        Assert.Empty(history.Removed);
        Assert.Null(history.Order);

        // An archived tab leaves by its identity, and a newly archived one goes last.
        var restored = space.ArchivedTabs[0];
        var archivedNow = space.ArchivedTabs[1] with { Tab = space.Tabs[0] with { Id = Guid.NewGuid() } };
        var archive = Assert.IsType<ArchiveChanged>(Assert.Single(Edited(space with {
            ArchivedTabs = [.. space.ArchivedTabs.Skip(1), archivedNow]
        })));
        Assert.Equal([restored.Tab.Id], archive.Removed);
        Assert.Equal([archivedNow], archive.Archived);
        Assert.Null(archive.Order);

        // Moving a tab changes no tab, so only the order arrives.
        var moved = Assert.IsType<TabsChanged>(Assert.Single(Edited(space with { Tabs = [.. space.Tabs.Skip(1), space.Tabs[0]] })));
        Assert.Empty(moved.Updated);
        Assert.Equal([.. space.Tabs.Skip(1).Select(tab => tab.Id), space.Tabs[0].Id], moved.Order);
    }

    /// An edit publishes only the sidebar lists it changes: a move publishes the list
    /// it moves within, a collapse and a new title or address publish none, a Start
    /// Page that becomes a web page publishes its section, and a deleted folder takes
    /// its list with it.
    [Fact]
    public void AnEditPublishesOnlyTheSidebarListsItChanges() {
        var session = MaximalSession().Current;
        var workspace = Guid.NewGuid();
        var folder = new FolderState(Guid.NewGuid(), TabPlacement.Current, "Folder");
        TabState Tab(string title, Guid? folderId = null, bool startPage = false) => new(Guid.NewGuid(), title,
            startPage ? null : $"https://example.com/{title}", null, null, "globe", null, null, null, TabPlacement.Current, folderId, null,
            DateTimeOffset.UnixEpoch, null, null, null, false);
        TabState[] loose = [Tab("first"), Tab("second"), Tab("third")];
        TabState[] filed = [Tab("inside", folder.Id), Tab("also inside", folder.Id)];
        var draft = Tab("draft", startPage: true);
        var start = session.Spaces[0] with { Tabs = [.. loose, .. filed, draft], Folders = [folder] };
        IReadOnlyList<Change> Published(SpaceState edited) =>
            SessionChanges.Publish(workspace, session with { Spaces = [start] }, session with { Spaces = [edited] });
        IEnumerable<(TabPlacement, Guid?)> Lists(SpaceState edited) =>
            Assert.Single(Published(edited).OfType<SidebarChanged>()).Lists.Select(list => (list.Section, list.FolderId));

        Assert.Equal([(TabPlacement.Current, null)], Lists(start with { Tabs = [loose[2], loose[0], loose[1], .. filed, draft] }));
        Assert.Equal([(TabPlacement.Current, folder.Id)], Lists(start with { Tabs = [.. loose, filed[1], filed[0], draft] }));
        Assert.Equal([(TabPlacement.Current, null)],
            Lists(start with { Tabs = [.. loose, .. filed, draft with { Url = "https://example.com/started" }] }));
        Assert.Equal([typeof(FoldersChanged)],
            Published(start with { Folders = [folder with { IsCollapsed = true }] }).Select(change => change.GetType()));
        Assert.Equal([typeof(TabsChanged)], Published(start with {
            Tabs = [loose[0] with { Title = "Retitled", Url = "https://example.com/moved-on" }, .. loose[1..], .. filed, draft]
        }).Select(change => change.GetType()));
        var deleted = Assert.Single(Published(start with {
            Tabs = [.. loose, .. filed.Select(tab => tab with { FolderId = null }), draft],
            Folders = []
        }).OfType<SidebarChanged>());
        Assert.Equal([(TabPlacement.Current, (Guid?)null)], deleted.Lists.Select(list => (list.Section, list.FolderId)));
        Assert.Equal([folder.Id], deleted.RemovedFolderIds);
    }

    /// A tab a window opens outside an intent the app runs, as a session's own
    /// work does: its changes wait in the pending batch, and the next intent
    /// answers them before its own, so a reader shows the new tab before the
    /// window that shows it and ends in the core's state.
    [Fact]
    public void AnIntentAnswersThePendingBatchBeforeItsOwnChanges() {
        using var app = new CrestApp();
        var opening = app.Send(new OpenWorkspace(WorkspaceKind.Persistent, TestWorkspaces.Seed(MaximalDocument())));
        var workspace = TestWorkspaces.Opened(opening);
        var authority = app.Workspace(workspace);
        var reader = SessionReader.Opening(opening);
        TestGrants.UnlockGuarded(app.Send, workspace, authority.Current);
        var space = authority.Current.Spaces[0];
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, CopyingWindowId: null, space.Id, [new(space.Id, space.Tabs[0].Id)],
            RestoresTabs: true));
        var opened = Guid.NewGuid();
        authority.Handle(new OpenTab(workspace, window, space.Id, opened, new TabContent("https://opened.example/", null, "Opened"),
            TabPlacement.Current, AfterTabId: null, Shows: true), DateTimeOffset.UtcNow, new TestIds());

        var answered = app.Send(new ShowTab(window, space.Id, space.Tabs[0].Id));

        Assert.Equal([typeof(TabsChanged), typeof(SidebarChanged), typeof(WindowChanged), typeof(TabsChanged), typeof(WindowChanged)],
            answered.Select(change => change.GetType()));
        Assert.Contains(((TabsChanged)answered[0]).Updated, tab => tab.Id == opened);
        Assert.Equal(opened, ((WindowChanged)answered[2]).Window.ShownTabs.Single(tab => tab.SpaceId == space.Id).TabId);
        Assert.Equal(space.Tabs[0].Id, Assert.Single(((TabsChanged)answered[3]).Updated).Id);
        Assert.Equal(space.Tabs[0].Id, ((WindowChanged)answered[4]).Window.ShownTabs.Single(tab => tab.SpaceId == space.Id).TabId);
        reader.Apply(answered);
        Assert.Equal(authority.Current, reader.State);
        Assert.Contains(reader.State.Spaces[0].Tabs, tab => tab.Id == opened);
    }
}
