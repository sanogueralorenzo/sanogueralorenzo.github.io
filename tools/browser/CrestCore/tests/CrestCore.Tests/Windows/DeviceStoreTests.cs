using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The device store: what each window shows lives beside the session in its
/// file, never in the session, survives a relaunch, is repaired when the
/// session changes under it, and was carried once from the records an
/// installed release kept.
public sealed partial class BrowserContractsTests {
    /// An app over a new file holding the installed session, with its
    /// persistent workspace and the session's Spaces.
    private static (CrestApp App, Guid Workspace, JsonArray Spaces) DeviceApp(StorageDirectory directory, JsonObject? core = null) {
        var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var (installedCore, installed, _) = InstalledDefaults();
        var session = core ?? installedCore;
        if (app.StoredSync is null) app.Send(new AdoptLegacySession(installed with { Core = Bytes(session) }, SeedSession()));
        // The file's session joins the device when a launch opens it.
        var (workspace, _) = TestWorkspaces.OpenStored(app);
        var opened = app.Workspace(workspace).Current;
        var spaces = StoredSessionCodec.Encode(opened)["spaces"]!.AsArray();
        TestGrants.UnlockGuarded(app.Send, workspace, opened);
        app.Drain();
        return (app, workspace, spaces);
    }

    private static Guid TabId(JsonNode space, int index) => SpaceId(space["tabs"]![index]!);

    private static WindowState Shown(IReadOnlyList<Change> changes) => Assert.IsType<WindowChanged>(changes[^1]).Window;

    private static Guid? ShownTab(WindowState window, Guid space) => window.ShownTabs.SingleOrDefault(tab => tab.SpaceId == space)?.TabId;

    [Fact]
    public void ASavedWindowReopensOnWhatItShowedAndTheSessionNeverHoldsIt() {
        using var directory = new StorageDirectory();
        var window = Guid.NewGuid();
        Guid second, tab, group;
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            second = SpaceId(spaces[1]!);
            tab = TabId(spaces[1]!, 3);
            group = Guid.Parse(spaces[0]!["splitGroups"]![0]!["id"]!["rawValue"]!.GetValue<string>());
            app.Send(new OpenWindow(window, workspace, Saved: true, CopyingWindowId: null, ShowingSpaceId: null, ShowingTabs: [], RestoresTabs: true));
            var touched = app.Send(new ShowTab(window, second, tab));
            Assert.Equal(tab, Assert.Single(Assert.Single(touched.OfType<TabsChanged>()).Updated).Id);
            Assert.Equal(second, Shown(touched).ShownSpaceId);
            var members = spaces[0]!["tabs"]!.AsArray().Count(item => item!["splitGroupID"]?["rawValue"]?.GetValue<string>() == group.ToString().ToUpperInvariant());
            var resized = Shown(app.Send(new ResizeSplitColumns(window, group, [.. Enumerable.Repeat(1.0, members)])));
            Assert.Equal(1.0 / members, resized.SplitColumnShares.Single().Shares[0], precision: 12);
            Assert.Equal([new WindowClosed(window)], Own(app.Send(new CloseWindow(window))));
        }

        var parts = StoredParts(directory.File);
        Assert.DoesNotContain("selectedTabID", Encoding.UTF8.GetString(parts["core"]), StringComparison.Ordinal);
        using var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadOnly);
        Assert.Equal(1, connection.ReadUserVersion());

        var (relaunched, persistent, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var restored = Shown(relaunched.Send(new OpenWindow(window, persistent, Saved: true, null, null, [], RestoresTabs: true)));
        Assert.Equal(second, restored.ShownSpaceId);
        Assert.Equal(tab, ShownTab(restored, second));
        Assert.Single(restored.SplitColumnShares);
        // A scene that restores only its Space keeps the Space and chooses tabs afresh.
        relaunched.Send(new CloseWindow(window));
        var spaceOnly = Shown(relaunched.Send(new OpenWindow(window, persistent, Saved: true, null, null, [], RestoresTabs: false)));
        Assert.Equal(second, spaceOnly.ShownSpaceId);
        Assert.Null(ShownTab(spaceOnly, second));
    }

    [Fact]
    public void ClosingThePersistentWorkspaceKeepsItsSavedWindowsForTheNextLaunch() {
        using var directory = new StorageDirectory();
        var window = Guid.NewGuid();
        Guid second;
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            second = SpaceId(spaces[1]!);
            app.Send(new OpenWindow(window, workspace, Saved: true, CopyingWindowId: null, ShowingSpaceId: null, ShowingTabs: [],
                RestoresTabs: true));
            app.Send(new ShowSpace(window, second));
            // The workspace closing closes its window, which the person never closed.
            Assert.Equal([new WindowClosed(window), new WorkspaceClosed(workspace)],
                app.Send(new CloseWorkspace(workspace)).Where(change => change is WindowClosed or WorkspaceClosed));
            Assert.Equal(new StoredSessionClosed(), Assert.Throws<Rejected>(() =>
                app.Send(new OpenWorkspace(WorkspaceKind.Persistent, Seed: null))).Rejection);
        }

        var (relaunched, persistent, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var restored = Shown(relaunched.Send(new OpenWindow(window, persistent, Saved: true, null, null, [], RestoresTabs: true)));
        Assert.Equal(second, restored.ShownSpaceId);
    }

    [Fact]
    public void WindowsFollowTheSessionAndOnlyTheOnesThatChangePublish() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var (first, second) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
        Guid showing = Guid.NewGuid(), elsewhere = Guid.NewGuid();
        app.Send(new OpenWindow(showing, workspace, Saved: true, null, null, [], true));
        app.Send(new OpenWindow(elsewhere, workspace, Saved: false, null, null, [], true));
        var shownTab = TabId(spaces[1]!, 2);
        app.Send(new ShowTab(showing, second, shownTab));
        app.Send(new ShowTab(elsewhere, second, TabId(spaces[1]!, 0)));
        app.Send(new ShowSpace(elsewhere, first));
        _ = app.Drain();

        // Another window deletes the tab this one shows: it shows nothing in that
        // Space, and the window that shows another Space is left alone.
        var session = app.Workspace(workspace);
        var space = session.Current.Spaces[1];
        var repaired = Assert.Single(app.Send(new DeleteTab(workspace, elsewhere, second, shownTab)).OfType<WindowChanged>()).Window;
        Assert.Equal(showing, repaired.Id);
        Assert.Null(ShownTab(repaired, second));
        Assert.Equal(space.Tabs.Count - 1, session.Current.Spaces[1].Tabs.Count);

        // Showing the Space again shows its fallback tab.
        app.Send(new ShowSpace(showing, first));
        var back = Shown(app.Send(new ShowSpace(showing, second)));
        Assert.Equal(Window.FallbackTab(session.Current.Spaces[1]), ShownTab(back, second));
        // A tab that is gone publishes nothing, and a window that is not open is refused.
        Assert.Empty(Own(app.Send(new ShowTab(showing, second, shownTab))));
        Assert.Equal(new WindowNotOpen(Guid.Empty), Assert.Throws<Rejected>(() => app.Send(new ShowSpace(Guid.Empty, first))).Rejection);
    }

    [Fact]
    public void OnlyWindowsOverThePersistentSessionAreSavedAndTheStoreKeepsTheSixteenUsedLast() {
        using var directory = new StorageDirectory();
        var windows = Enumerable.Range(0, Device.MaximumSavedWindows + 1).Select(_ => Guid.NewGuid()).ToArray();
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            var memoryWorkspace = TestWorkspaces.Open(app, SavedSession().Document["session"]!);
            Assert.Equal(new UnsavedWorkspace(memoryWorkspace),
                Assert.Throws<Rejected>(() => app.Send(new OpenWindow(Guid.NewGuid(), memoryWorkspace, true, null, null, [], true))).Rejection);
            app.Send(new OpenWindow(Guid.NewGuid(), memoryWorkspace, Saved: false, null, null, [], true));
            foreach (var window in windows) app.Send(new OpenWindow(window, workspace, Saved: true, null, null, [], true));
            // Using the first window again keeps it; the second is now the oldest.
            app.Send(new ShowSpace(windows[0], SpaceId(spaces[1]!)));
            // A workspace that closes takes its windows with it.
            app.Send(new CloseWorkspace(memoryWorkspace));
        }
        using var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadOnly);
        var stored = connection.ReadDevice().Windows.Select(record => record.Id).ToHashSet();
        Assert.Equal(Device.MaximumSavedWindows, stored.Count);
        Assert.Contains(windows[0], stored);
        Assert.DoesNotContain(windows[1], stored);
    }

    [Fact]
    public void AWindowOnlyChangeIsPendingUntilItIsWritten() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var (window, second) = (Guid.NewGuid(), SpaceId(spaces[1]!));
        Assert.NotEqual(second, Shown(app.Send(new OpenWindow(window, workspace, Saved: true, null, null, [], true))).ShownSpaceId);
        _ = DrainUntil(app, _ => app.Query(new PendingSave()).Revision is null);
        Assert.Null(app.Query(new PendingSave()).Revision);
        var revision = app.Workspace(workspace).Revision;

        // Another writer holds the file, so the device store cannot write behind yet.
        using var holder = SqliteConnection.Open(directory.File, Sqlite.OpenReadWrite);
        holder.Execute("BEGIN IMMEDIATE");
        Assert.Equal(second, Shown(app.Send(new ShowSpace(window, second))).ShownSpaceId);
        Assert.Equal(revision, app.Workspace(workspace).Revision);
        var pending = Assert.NotNull(app.Query(new PendingSave()).Revision);
        Assert.NotEqual(second, holder.ReadDevice().Windows.Single(record => record.Id == window).ShownSpaceId);
        holder.Execute("ROLLBACK");

        var announced = DrainUntil(app, changes => changes.OfType<Saved>().Any(saved => saved.Revision >= pending));
        Assert.Contains(announced, change => change is Saved saved && saved.Revision >= pending);
        Assert.Null(app.Query(new PendingSave()).Revision);
        Assert.Equal(second, holder.ReadDevice().Windows.Single(record => record.Id == window).ShownSpaceId);
    }

    [Fact]
    public void TheWindowRecordsAnInstalledReleaseKeptAreCarriedOnceWithTheirLayouts() {
        using var directory = new StorageDirectory();
        var (core, _, _) = InstalledDefaults();
        var spaces = core["spaces"]!.AsArray();
        var (first, second) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
        var legacyTab = TabId(spaces[1]!, 2);
        Guid captured = Guid.NewGuid(), older = Guid.NewGuid();
        var group = Guid.NewGuid();
        JsonObject Wrapped(Guid id) => SwiftId(id);
        var records = new JsonArray(
            new JsonObject {
                ["id"] = Wrapped(older),
                ["selectedSpaceID"] = Wrapped(first),
                ["selectedTabIDsBySpace"] = new JsonArray(Wrapped(first), Wrapped(TabId(spaces[0]!, 1)))
            },
            new JsonObject {
                ["id"] = Wrapped(captured),
                ["selectedSpaceID"] = Wrapped(second),
                ["selectedTabIDsBySpace"] = new JsonArray(Wrapped(first), Wrapped(TabId(spaces[0]!, 4))),
                ["capturedSpaceIDs"] = new JsonArray(Wrapped(first), Wrapped(second)),
                ["sidebarWidth"] = 277.5,
                ["sidebarIsPresented"] = false,
                ["splitColumnFractionsByGroup"] = new JsonArray(Wrapped(group), new JsonArray(0.25, 0.75))
            });
        {
            var (app, _, _) = DeviceApp(directory, core);
            using var disposal = app;
            var adopted = Assert.IsType<WindowRecordsAdopted>(Assert.Single(Own(app.Send(new AdoptWindowRecords(Bytes(records))))));
            Assert.Equal([new WindowLayout(older, null, null), new WindowLayout(captured, 277.5, false)], adopted.Layouts);
            Assert.Empty(Own(app.Send(new AdoptWindowRecords(Bytes(records)))));
        }
        var (relaunched, workspace, _) = DeviceApp(directory, core);
        using var relaunchedDisposal = relaunched;
        Assert.Empty(Own(relaunched.Send(new AdoptWindowRecords(Bytes(records)))));
        // A record that remembered its Spaces shows nothing where it chose nothing.
        var capturedWindow = Shown(relaunched.Send(new OpenWindow(captured, workspace, true, null, null, [], true)));
        Assert.Equal(second, capturedWindow.ShownSpaceId);
        Assert.Null(ShownTab(capturedWindow, second));
        Assert.Contains(capturedWindow.ShownTabs, tab => tab.SpaceId == second);
        // An older record takes the tab the release kept in the session.
        var olderWindow = Shown(relaunched.Send(new OpenWindow(older, workspace, true, null, null, [], true)));
        Assert.Equal(first, olderWindow.ShownSpaceId);
        Assert.Equal(legacyTab, ShownTab(olderWindow, second));
    }

    [Fact]
    public void ALaunchReopensTheWindowsLeftOpenBackToFrontOrTheOneUsedLast() {
        using var directory = new StorageDirectory();
        Guid back = Guid.NewGuid(), closed = Guid.NewGuid(), minimized = Guid.NewGuid(), front = Guid.NewGuid();
        var installed = LaunchEnvironment.Installed;
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            foreach (var window in new[] { back, closed, minimized, front })
                app.Send(new OpenWindow(window, workspace, Saved: true, null, null, [], RestoresTabs: true));
            app.Send(new OpenWindow(Guid.NewGuid(), workspace, Saved: false, null, null, [], RestoresTabs: true));
            // A window the person closed is not reopened, and one never saved is not either.
            app.Send(new CloseWindow(closed));
            Assert.Equal([back, minimized, front], app.Query(new LaunchWindows(installed)).WindowIds);

            // At quit the platform says how its windows stack; one it left out
            // goes behind. Once the quit is allowed, the windows closing as
            // the app goes are still the ones to reopen.
            app.Send(new RememberWindowsForLaunch([back, Guid.NewGuid(), front]));
            Assert.Contains(app.Send(new PrepareToQuit(Guid.NewGuid())), change => change is CloseReady { Allowed: true });
            foreach (var window in new[] { back, minimized, front }) app.Send(new CloseWindow(window));
        }
        {
            var (relaunched, workspace, _) = DeviceApp(directory);
            using var disposal = relaunched;
            var plan = relaunched.Query(new LaunchWindows(installed));
            Assert.Equal([minimized, front, back], plan.WindowIds);
            Assert.Equal(back, plan.StartupWindowId);
            // With every window closed, the Dock brings back the one used last.
            relaunched.Send(new OpenWindow(minimized, workspace, Saved: true, null, null, [], RestoresTabs: true));
            Assert.Equal(new ReopenedWindow(minimized, OpensWindow: false), relaunched.Query(new WindowToReopen([minimized])));
            relaunched.Send(new CloseWindow(minimized));
            Assert.Equal(new ReopenedWindow(minimized, OpensWindow: true), relaunched.Query(new WindowToReopen([])));
            relaunched.Send(new RememberWindowsForLaunch([]));
        }
        var (again, _, _) = DeviceApp(directory);
        using var againDisposal = again;
        Assert.Equal([minimized], again.Query(new LaunchWindows(installed)).WindowIds);
        using var fresh = new StorageDirectory();
        var (first, _, _) = DeviceApp(fresh);
        using var firstDisposal = first;
        Assert.NotEqual(Guid.Empty, Assert.Single(first.Query(new LaunchWindows(installed)).WindowIds));
    }

    [Fact]
    public void TheChromiumWindowListIsCarriedOnceAndNeverOverWindowsTheDeviceReopens() {
        using var directory = new StorageDirectory();
        Guid[] listed = [Guid.NewGuid(), Guid.NewGuid()];
        var installed = LaunchEnvironment.Installed;
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            foreach (var window in listed) app.Send(new OpenWindow(window, workspace, Saved: true, null, null, [], RestoresTabs: true));
            foreach (var window in listed) app.Send(new CloseWindow(window));
            Assert.Empty(Own(app.Send(new AdoptOpenWindows(listed))));
            Assert.Equal(listed, app.Query(new LaunchWindows(installed)).WindowIds);
            app.Send(new AdoptOpenWindows([listed[1]]));
            Assert.Equal(listed, app.Query(new LaunchWindows(installed)).WindowIds);
        }
        var (relaunched, _, _) = DeviceApp(directory);
        using (relaunched) {
            relaunched.Send(new AdoptOpenWindows([Guid.NewGuid()]));
            Assert.Equal(listed, relaunched.Query(new LaunchWindows(installed)).WindowIds);
        }

        // A device the other composition already reopens windows for keeps them.
        using var other = new StorageDirectory();
        var (kept, keptWorkspace, _) = DeviceApp(other);
        using var keptDisposal = kept;
        var own = Guid.NewGuid();
        kept.Send(new OpenWindow(own, keptWorkspace, Saved: true, null, null, [], RestoresTabs: true));
        kept.Send(new AdoptOpenWindows(listed));
        Assert.Equal([own], kept.Query(new LaunchWindows(installed)).WindowIds);
    }

    [Fact]
    public void ADraggedTabMayLeaveOnlyAloneFromAnUnchangedSpace() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, false, null, null, [], true));
        var (space, profile, tab) = (SpaceId(spaces[0]!), Guid.Parse(spaces[0]!["profile"]!["id"]!.GetValue<string>()), TabId(spaces[0]!, 0));
        Assert.Equal(new TearOffPermission(true, null), app.Query(new CanTearOff(window, space, profile, tab, null)));
        Assert.Equal(new TearOffPermission(true, null), app.Query(new CanTearOff(window, space, profile, tab, [tab])));
        Assert.Equal(TearOffRefusal.SeveralTabs, app.Query(new CanTearOff(window, space, profile, tab, [tab, TabId(spaces[0]!, 1)])).Reason);
        Assert.Equal(TearOffRefusal.SpaceChanged, app.Query(new CanTearOff(window, space, Guid.NewGuid(), tab, null)).Reason);
        Assert.Equal(TearOffRefusal.TabGone, app.Query(new CanTearOff(window, space, profile, Guid.NewGuid(), null)).Reason);
    }

    [Fact]
    public void DismissingAShownTabReturnsToTheTabTheWindowShowedBefore() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var space = SpaceId(spaces[1]!);
        var (earlier, dismissed) = (TabId(spaces[1]!, 0), TabId(spaces[1]!, 2));
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, space, [], RestoresTabs: false));
        app.Send(new ShowTab(window, space, earlier));
        app.Send(new ShowTab(window, space, dismissed));
        // A window that no longer shows the tab is left alone.
        Assert.Empty(Own(app.Send(new DismissShownTab(window, space, earlier))));

        var returned = app.Send(new DismissShownTab(window, space, dismissed));
        Assert.Equal(earlier, Assert.Single(Assert.Single(returned.OfType<TabsChanged>()).Updated).Id);
        Assert.Equal(earlier, ShownTab(Shown(returned), space));
        // With nothing left to return to, it shows nothing there.
        Assert.Null(ShownTab(Shown(app.Send(new DismissShownTab(window, space, earlier))), space));
    }

    [Fact]
    public void ASpaceNoWindowChoseATabForShowsItsFirstOpenThenPinnedThenFirstTab() {
        using var app = new CrestApp();
        Assert.Equal(1, app.Query(new FallbackTab([TabPlacement.Pinned, TabPlacement.Current])).Index);
        Assert.Equal(1, app.Query(new FallbackTab([TabPlacement.Saved, TabPlacement.Pinned])).Index);
        Assert.Equal(0, app.Query(new FallbackTab([TabPlacement.Saved])).Index);
        Assert.Null(app.Query(new FallbackTab([])).Index);
    }
}
