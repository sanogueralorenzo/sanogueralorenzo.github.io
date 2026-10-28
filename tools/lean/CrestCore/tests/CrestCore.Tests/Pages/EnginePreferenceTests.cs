using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Global engine choice, persistence, capabilities and opener ownership.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void TheGlobalEngineRoutesNewPagesWithoutMovingExistingPages() {
        using var app = new CrestApp();
        var chromium = new RecordingEngine();
        var webKit = new RecordingEngine();
        app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, [.. EngineCapability.Required, EngineCapability.Extensions], true), chromium.Run);
        app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, false), webKit.Run);
        var workspace = TestWorkspaces.Open(app, SavedSession().Document["session"]!);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, false, null, null, [], true));
        var space = app.Workspace(workspace).Current.Spaces.First();
        var tab = space.Tabs.First(tab => tab.Url is not null);
        var changed = app.Send(new SelectDefaultEngine(EngineKind.WebKit));
        Assert.Equal(EngineKind.WebKit, Assert.Single(changed.OfType<EnginesChanged>()).Roster.Engines.Single(engine => engine.IsDefault).Kind);
        Assert.Equal(EngineKind.WebKit, Assert.Single(changed.OfType<EnginePreferencesChanged>()).Preferences.DefaultEngine);
        Assert.Contains(EngineCapability.Extensions, Assert.Single(changed.OfType<EnginesChanged>()).Roster.Offered);
        Assert.Empty(chromium.Commands);
        Assert.Empty(webKit.Commands);
        var first = Guid.NewGuid();
        app.Send(new OpenPage(first, workspace, space.Id, tab.Id, window));
        Assert.Equal(EngineKind.WebKit, CreatedOn(first, chromium, webKit));
        var webKitEngine = app.Engines.Registered(EngineKind.WebKit)!;
        app.Report(webKitEngine, new PageCreated(first));

        app.Send(new SelectDefaultEngine(EngineKind.Chromium));
        Assert.DoesNotContain(webKit.Commands, command => command is ClosePage);
        app.Send(new Navigate(first, "https://other.example/path"));
        Assert.Equal(new LoadPage(first, "https://other.example/path"), webKit.Commands[^1]);
        var second = Guid.NewGuid();
        var secondTab = Guid.NewGuid();
        app.Send(new OpenTab(workspace, window, space.Id, secondTab,
            new TabContent("https://another.example/", null, null), TabPlacement.Current, null, false));
        app.Send(new OpenPage(second, workspace, space.Id, secondTab, window));
        Assert.Equal(EngineKind.Chromium, CreatedOn(second, chromium, webKit));
        app.Send(new SelectDefaultEngine(null));
        Assert.Null(app.Query(new GetEnginePreferences()).DefaultEngine);
        Assert.DoesNotContain(webKit.Commands, command => command is ClosePage);
    }

    [Fact]
    public void AnEnginePreferenceSurvivesRelaunchAndAnUnavailableEngineWithoutStartingIt() {
        using var directory = new StorageDirectory();
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, true), _ => { });
            app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, false), _ => { });
            app.Send(new SelectDefaultEngine(EngineKind.WebKit));
        }
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            var commands = new List<EngineCommand>();
            // The preference can be available before the composition default registers.
            app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, false), commands.Add);
            app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, true), commands.Add);
            Assert.Equal(EngineKind.WebKit, app.Query(new GetEnginePreferences()).DefaultEngine);
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

    /// The engine of the `CreatePage` that opened `page`, by the binding that ran it.
    private static EngineKind CreatedOn(Guid page, RecordingEngine chromium, RecordingEngine webKit) =>
        chromium.Commands.OfType<CreatePage>().Any(command => command.PageId == page) ? EngineKind.Chromium
        : webKit.Commands.OfType<CreatePage>().Any(command => command.PageId == page) ? EngineKind.WebKit
        : throw new InvalidOperationException("No engine created the page.");

    [Fact]
    public void AnEngineOffersItsFeaturesAsTheDefaultOrWhileAPageIsOpenOnIt() {
        var session = SavedSession();
        var (app, webKit, _, workspace, window) = PageHost(session.Document["session"]!);
        using var disposal = app;
        IReadOnlyList<Change> Offering(IReadOnlyList<Change> changes) => [.. changes.Where(change => change is EnginesChanged or ShortcutsChanged)];
        bool OffersReader(IReadOnlyList<Change> changes) =>
            Assert.Single(changes.OfType<EnginesChanged>()).Roster.Offered.Contains(EngineCapability.Reader)
            && Assert.Single(changes.OfType<ShortcutsChanged>()).Bindings.Any(binding => binding.Command == ShortcutCommand.ToggleReaderMode);

        // PageHost's default WebKit lacks Reader, so a registered engine with it that no page uses adds nothing.
        var chromium = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, [.. EngineCapability.Required, EngineCapability.Reader],
            IsDefault: false), _ => { });
        var registered = Assert.Single(app.Drain().OfType<EnginesChanged>()).Roster;
        Assert.Equal([EngineKind.Chromium, EngineKind.WebKit], registered.Engines.Select(engine => engine.Kind));
        Assert.Equal(EngineCapability.Required, registered.Offered);

        // Its first page offers what it supports, and its last page going takes that back.
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, session.Space, session.Tab, window));
        app.Report(webKit, new PageCreated(page));
        app.Drain();
        app.Send(new RehostPage(page, EngineKind.Chromium));
        app.Report(webKit, new BeforeUnloadAnswered(page, Proceeds: true));
        var opened = Offering(app.Drain());
        Assert.True(OffersReader(opened));
        app.Report(chromium, new PageCreated(page));
        Assert.False(OffersReader(Offering(app.Send(new ReleasePage(page, KeepsState: false)))));
    }

    [Fact]
    public void EveryEngineButTheDefaultBadgesItsPagesOnceMoreThanOneIsRegistered() {
        using var app = new CrestApp();
        Assert.Empty(EngineRoster.Unregistered.Badged);

        // One engine badges nothing: every page runs on it.
        app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true), _ => { });
        Assert.Empty(Assert.Single(app.Drain().OfType<EnginesChanged>()).Roster.Badged);

        // A second engine badges its own pages, whichever engine is the default.
        var chromium = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: false),
            _ => { });
        Assert.Equal([EngineKind.Chromium], Assert.Single(app.Drain().OfType<EnginesChanged>()).Roster.Badged);

        // Once it goes, the default's pages stay unbadged.
        app.UnregisterEngine(chromium);
        Assert.Empty(Assert.Single(app.Drain().OfType<EnginesChanged>()).Roster.Badged);
    }

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
        app.Send(new SelectDefaultEngine(EngineKind.WebKit));
        var (_, opener) = LiveTab(app, webKit, workspace, window, space, "https://video.example/login");
        Assert.Equal(EngineKind.WebKit, CreatedOn(opener, chromiumBinding, webKitBinding));
        app.Send(new SelectDefaultEngine(EngineKind.Chromium));

        // A tab or popup the page opens keeps WebKit even after the default changes.
        var tab = Guid.NewGuid();
        app.Send(new OpenTab(workspace, window, space, tab, new TabContent(signIn, View: null, Title: null), TabPlacement.Current,
            AfterTabId: null, Shows: true));
        var opened = Guid.NewGuid();
        app.Send(new OpenPage(opened, workspace, space, tab, window, OpenerPageId: opener));
        var peek = Guid.NewGuid();
        app.Send(new OpenPage(peek, workspace, space, null, window, TransientPresentation.Settings, OpenerPageId: opener));
        app.Report(webKit, new PageOffered(Guid.NewGuid(), profile, opener, WindowId: null, SpaceId: null, signIn, Foreground: true));
        var offered = Assert.Single(app.Drain().OfType<OfferedPageAdopted>()).PageId;
        Assert.All(new[] { opened, peek }, page => Assert.Equal(EngineKind.WebKit, CreatedOn(page, chromiumBinding, webKitBinding)));
        Assert.Equal(offered, Assert.IsType<AdoptOfferedPage>(webKitBinding.Commands[^1]).PageId);
        Assert.DoesNotContain(chromiumBinding.Commands, command => command is AdoptOfferedPage);

        // Redirects and typed navigation stay on the opener's engine. An explicit move switches it.
        app.Report(webKit, new PageCreated(opened));
        app.Report(webKit, new NavigationStarted(opened, signIn, SameDocument: false));
        Assert.DoesNotContain(chromiumBinding.Commands, command => command is CreatePage creation && creation.PageId == opened);
        app.Send(new Navigate(opened, signIn));
        Assert.Equal(new LoadPage(opened, signIn), webKitBinding.Commands[^1]);
        app.Send(new RehostPage(opened, EngineKind.Chromium));
        Assert.Equal(new CheckBeforeUnload(opened), webKitBinding.Commands[^1]);
        app.Report(webKit, new BeforeUnloadAnswered(opened, Proceeds: true));
        Assert.Equal(new ClosePage(opened, KeepsState: true), webKitBinding.Commands[^1]);
        Assert.Equal(opened, Assert.IsType<CreatePage>(chromiumBinding.Commands[^1]).PageId);

        // A fresh page, or one whose opener is gone, uses the global default.
        var (typed, orphaned) = (Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenPage(typed, workspace, space, null, window, TransientPresentation.Authentication));
        app.Send(new ReleasePage(peek, KeepsState: false));
        app.Send(new OpenPage(orphaned, workspace, space, null, window, TransientPresentation.Settings, OpenerPageId: peek));
        Assert.All(new[] { typed, orphaned }, page => Assert.Equal(EngineKind.Chromium, CreatedOn(page, chromiumBinding, webKitBinding)));
    }

}
