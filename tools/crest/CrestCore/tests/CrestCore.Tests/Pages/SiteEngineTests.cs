using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Which engine a site's pages open on: the device store keeps the choices
/// made in the persistent session, every other Space's choices live in
/// memory, and a tab's page opens on the engine chosen for its site.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void AnEnginePreferenceSurvivesRelaunchAndAnUnavailableEngineWithoutStartingIt() {
        using var directory = new StorageDirectory();
        var origin = new SiteOrigin("https", "kept.example", 443);
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, true), _ => { });
            app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, false), _ => { });
            app.Send(new SelectDefaultEngine(EngineKind.WebKit));
            app.Send(new EditEngineRule(null, origin, EngineKind.Chromium));
        }
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            var commands = new List<EngineCommand>();
            // The preference can be available before the composition default registers.
            app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, false), commands.Add);
            app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, true), commands.Add);
            Assert.Equal(EngineKind.WebKit, app.Query(new GetEnginePreferences()).DefaultEngine);
            Assert.Equal([new SiteEngineRule(origin, EngineKind.Chromium)], app.Query(new GetEnginePreferences()).Rules);
            Assert.Equal(EngineKind.WebKit, app.Drain().OfType<EnginesChanged>().Last().Roster.Engines.Single(engine => engine.IsDefault).Kind);
            Assert.Empty(commands);
        }
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, true), _ => { });
            Assert.Equal(EngineKind.Chromium, app.Drain().OfType<EnginesChanged>().Last().Roster.Engines.Single(engine => engine.IsDefault).Kind);
            Assert.Equal(EngineKind.WebKit, app.Query(new GetEnginePreferences()).DefaultEngine);
        }
    }

    private static SiteOrigin? Origin(TabState tab) => tab.Url is { } url ? new WebAddress(url).Origin : null;

    /// The engine of the `CreatePage` that opened `page`, by the binding that ran it.
    private static EngineKind CreatedOn(Guid page, RecordingEngine chromium, RecordingEngine webKit) =>
        chromium.Commands.OfType<CreatePage>().Any(command => command.PageId == page) ? EngineKind.Chromium
        : webKit.Commands.OfType<CreatePage>().Any(command => command.PageId == page) ? EngineKind.WebKit
        : throw new InvalidOperationException("No engine created the page.");

    [Fact]
    public void APageAnotherPageOpensRunsOnItsOpenersEngineWhateverItsSiteAndOnlyThePersonMovesIt() {
        var session = TwoSpaceSession();
        var (space, profile) = (SpaceId(session["spaces"]![0]!), ProfileId(session["spaces"]![0]!));
        using var app = new CrestApp();
        var (chromiumBinding, webKitBinding) = (new RecordingEngine(), new RecordingEngine());
        var chromium = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true),
            chromiumBinding.Run);
        var webKit = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: false),
            webKitBinding.Run);
        var workspace = TestWorkspaces.Open(app, session);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        const string signIn = "https://accounts.example/sign-in";
        app.Send(new ChooseSiteEngine(space, new WebAddress("https://video.example/").Origin!, EngineKind.WebKit));
        app.Send(new ChooseSiteEngine(space, new WebAddress(signIn).Origin!, EngineKind.Chromium));
        var (_, opener) = LiveTab(app, webKit, workspace, window, space, "https://video.example/login");
        Assert.Equal(EngineKind.WebKit, CreatedOn(opener, chromiumBinding, webKitBinding));

        // A tab, Peek or window the page opens runs on WebKit, though the site it heads to chose Chromium.
        var tab = Guid.NewGuid();
        app.Send(new OpenTab(workspace, window, space, tab, new TabContent(signIn, View: null, Title: null), TabPlacement.Current,
            AfterTabId: null, Shows: true));
        var opened = Guid.NewGuid();
        app.Send(new OpenPage(opened, workspace, space, tab, window, OpenerPageId: opener));
        var peek = Guid.NewGuid();
        app.Send(new OpenPage(peek, workspace, space, null, window, TransientPresentation.Peek, OpenerPageId: opener));
        app.Report(webKit, new PageOffered(Guid.NewGuid(), profile, opener, WindowId: null, SpaceId: null, signIn, Foreground: true));
        var offered = Assert.Single(app.Drain().OfType<OfferedPageAdopted>()).PageId;
        Assert.All(new[] { opened, peek }, page => Assert.Equal(EngineKind.WebKit, CreatedOn(page, chromiumBinding, webKitBinding)));
        Assert.Equal(offered, Assert.IsType<AdoptOfferedPage>(webKitBinding.Commands[^1]).PageId);
        Assert.DoesNotContain(chromiumBinding.Commands, command => command is AdoptOfferedPage);

        // Its own navigations keep it there; an address the person asks for follows the site's choice.
        app.Report(webKit, new PageCreated(opened));
        app.Report(webKit, new NavigationStarted(opened, signIn, SameDocument: false));
        Assert.DoesNotContain(chromiumBinding.Commands, command => command is CreatePage creation && creation.PageId == opened);
        app.Send(new Navigate(opened, signIn));
        Assert.Equal(new CheckBeforeUnload(opened), webKitBinding.Commands[^1]);
        app.Report(webKit, new BeforeUnloadAnswered(opened, Proceeds: true));
        Assert.Equal(new ClosePage(opened, KeepsState: true), webKitBinding.Commands[^1]);
        Assert.Equal(opened, Assert.IsType<CreatePage>(chromiumBinding.Commands[^1]).PageId);

        // A page the person opens follows the site's choice, as does one whose opener the core no longer hosts.
        var (typed, orphaned) = (Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenPage(typed, workspace, space, null, window, TransientPresentation.QuickWindow));
        app.Send(new ReleasePage(peek, KeepsState: false));
        app.Send(new OpenPage(orphaned, workspace, space, null, window, TransientPresentation.Peek, OpenerPageId: peek));
        Assert.All(new[] { typed, orphaned }, page => Assert.Equal(EngineKind.Chromium, CreatedOn(page, chromiumBinding, webKitBinding)));
    }

    [Fact]
    public void ATabsPageOpensOnTheEngineChosenForItsSiteAndOnlyThePersistentSessionsChoicesAreKept() {
        using var directory = new StorageDirectory();
        Guid spaceId, chosenTab, otherTab;
        SiteOrigin site;
        {
            var (app, workspace, _) = DeviceApp(directory);
            using var disposal = app;
            var (chromium, webKit) = (new RecordingEngine(), new RecordingEngine());
            var chromiumEngine = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true),
                chromium.Run);
            app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: false), webKit.Run);
            spaceId = app.Workspace(workspace).Current.Spaces.First(space => space.Settings.AccessPolicy == SpaceAccessPolicy.Open).Id;
            var window = Guid.NewGuid();
            app.Send(new OpenWindow(window, workspace, Saved: false, null, spaceId, [], RestoresTabs: true));
            foreach (var address in new[] { "https://video.example/watch", "https://news.example/today" })
                app.Send(new OpenAddress(workspace, window, spaceId, Guid.NewGuid(), address));
            var space = app.Workspace(workspace).Current.Spaces.Single(space => space.Id == spaceId);
            var tabs = new[] { "video.example", "news.example" }.Select(host => space.Tabs.Single(tab => Origin(tab)?.Host == host)).ToArray();
            (chosenTab, otherTab, site) = (tabs[0].Id, tabs[1].Id, Origin(tabs[0])!);

            // Before any choice, the page opens on the default engine and keeps its state when it closes.
            var before = Guid.NewGuid();
            app.Send(new OpenPage(before, workspace, spaceId, chosenTab, window));
            Assert.Equal(EngineKind.Chromium, CreatedOn(before, chromium, webKit));
            app.Report(chromiumEngine, new PageCreated(before));
            app.Send(new ReleasePage(before, KeepsState: true));
            app.Report(chromiumEngine, new PageClosed(before, new PageRestoreState(tabs[0].Url!, [1, 2, 3])));

            // The site's next page opens on the chosen engine, which never takes what another engine kept.
            app.Send(new ChooseSiteEngine(spaceId, site, EngineKind.WebKit));
            var chosen = Guid.NewGuid();
            app.Send(new OpenPage(chosen, workspace, spaceId, chosenTab, window));
            Assert.Equal(new CreatePage(chosen, space.ProfileId, IsPrivate: false, window, RestoreState: null),
                webKit.Commands.OfType<CreatePage>().Single());
            var other = Guid.NewGuid();
            app.Send(new OpenPage(other, workspace, spaceId, otherTab, window));
            Assert.Equal(EngineKind.Chromium, CreatedOn(other, chromium, webKit));

            // A private Space's choice holds there alone and stays in memory.
            var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)));
            var privateSpace = app.Workspace(privateWorkspace).Current.Spaces.Single().Id;
            var otherSite = Origin(tabs[1])!;
            app.Send(new ChooseSiteEngine(privateSpace, otherSite, EngineKind.WebKit));
            app.Send(new ReleasePage(other, KeepsState: false));
            var stillDefault = Guid.NewGuid();
            app.Send(new OpenPage(stillDefault, workspace, spaceId, otherTab, window));
            Assert.Equal(EngineKind.Chromium, CreatedOn(stillDefault, chromium, webKit));

            // An engine this device did not register, an origin that is not one and a locked Space are refused.
            using (var webKitOnly = new CrestApp()) {
                webKitOnly.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true), _ => { });
                Assert.Equal(new UnregisteredEngine(EngineKind.Chromium), Assert.Throws<Rejected>(() =>
                    webKitOnly.Send(new ChooseSiteEngine(Guid.NewGuid(), site, EngineKind.Chromium))).Rejection);
            }
            var blank = new SiteOrigin("https", "", 443);
            Assert.Equal(new InvalidSiteOrigin(blank), Assert.Throws<Rejected>(() =>
                app.Send(new ChooseSiteEngine(spaceId, blank, EngineKind.WebKit))).Rejection);
            var guarded = app.Workspace(workspace).Current.Spaces.First(space => space.Settings.AccessPolicy != SpaceAccessPolicy.Open).Id;
            app.Send(new LockSpace(guarded));
            Assert.Equal(new SpaceLocked(guarded), Assert.Throws<Rejected>(() =>
                app.Send(new ChooseSiteEngine(guarded, site, EngineKind.WebKit))).Rejection);
        }

        // The persistent session's choice is kept, and the private Space's is not.
        var (relaunched, persistent, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var (chromiumAgain, webKitAgain) = (new RecordingEngine(), new RecordingEngine());
        relaunched.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true),
            chromiumAgain.Run);
        relaunched.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: false), webKitAgain.Run);
        var relaunchedWindow = Guid.NewGuid();
        relaunched.Send(new OpenWindow(relaunchedWindow, persistent, Saved: false, null, null, [], RestoresTabs: true));
        var (kept, unkept) = (Guid.NewGuid(), Guid.NewGuid());
        relaunched.Send(new OpenPage(kept, persistent, spaceId, chosenTab, relaunchedWindow));
        relaunched.Send(new OpenPage(unkept, persistent, spaceId, otherTab, relaunchedWindow));
        Assert.Equal(EngineKind.WebKit, CreatedOn(kept, chromiumAgain, webKitAgain));
        Assert.Equal(EngineKind.Chromium, CreatedOn(unkept, chromiumAgain, webKitAgain));
    }
}
