using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A page's live state: what its engine shows reaches readers once per real
/// change and once per drain, a failure stays until the page moves on, and a
/// load the person asks for resolves by the core's address rules.
public sealed partial class BrowserContractsTests {
    /// A live page for the fixture tab of a saved session's first Space, on
    /// the default engine of `PageHost`.
    private static (CrestApp App, Engine Engine, RecordingEngine Binding, Guid Page, Guid Workspace, Guid Window, Guid Space, Guid Tab)
        LivePage() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var (app, engine, binding, workspace, window) = PageHost(session);
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, fixture.Space, fixture.Tab, window));
        app.Report(engine, new PageCreated(page));
        app.Drain();
        return (app, engine, binding, page, workspace, window, fixture.Space, fixture.Tab);
    }

    private static PageSnapshot Showing(string url, string title = "", bool isLoading = false) =>
        PageSnapshot.Blank with { Url = url, Title = title, IsLoading = isLoading };

    private static PageLiveState Live(IReadOnlyList<Change> changes) => Assert.IsType<PageChanged>(Assert.Single(changes)).Page.Live;

    [Fact]
    public void APagesStateReachesReadersOnlyWhenItChangesAndOncePerDrain() {
        var (app, engine, _, page, workspace, window, space, _) = LivePage();
        using var disposal = app;
        var other = Guid.NewGuid();
        app.Send(new OpenPage(other, workspace, space, null, window));

        // Reports between drains reach readers once, where the latest falls.
        app.Report(engine, new PageStateChanged(page, Showing("https://example.com/", isLoading: true)));
        app.Report(engine, new PageCreated(other));
        app.Report(engine, new PageStateChanged(page, Showing("https://example.com/", "Example")));
        var drained = app.Drain();
        Assert.Equal([other, page], drained.Select(change => Assert.IsType<PageChanged>(change).Page.Id));
        Assert.Equal(PageLiveState.Blank with { Url = "https://example.com/", Title = "Example" },
            Assert.IsType<PageChanged>(drained[^1]).Page.Live);

        // The same state again, or a report about a page that is gone, changes nothing.
        app.Report(engine, new PageStateChanged(page, Showing("https://example.com/", "Example")));
        app.Report(engine, new PageStateChanged(Guid.NewGuid(), Showing("https://stale.example/")));
        Assert.Empty(app.Drain());
    }

    [Fact]
    public void AFailureStaysUntilThePageMovesOnAndLetsItReturnToTheDocumentBehind() {
        var (app, engine, _, page, _, _, _, _) = LivePage();
        using var disposal = app;
        app.Report(engine, new PageStateChanged(page, Showing("https://example.com/", "Example")));
        app.Drain();
        var failure = new PageFailure(NavigationError.CannotFindServer, "https://missing.example/", ReplacedDocument: false,
            "NSURLErrorDomain", -1003);

        // A failure over the document the page still shows lets it go back there.
        app.Report(engine, new NavigationFailed(page, failure));
        var failed = Live(app.Drain());
        Assert.Equal((failure, true, "https://missing.example/"), (failed.Failure, failed.CanGoBack, failed.Address));

        // An engine retrying on its own keeps showing the failure; leaving it ends it.
        app.Report(engine, new NavigationStarted(page, "https://missing.example/", SameDocument: false));
        Assert.Empty(app.Drain());
        var left = Live(app.Send(new LeavePageFailure(page)));
        Assert.Equal((null, false), (left.Failure, left.CanGoBack));
        Assert.Empty(app.Send(new LeavePageFailure(page)));

        // A committed error page replaced the document, so going back is the engine's.
        app.Report(engine, new NavigationFailed(page, failure with { ReplacedDocument = true }));
        Assert.False(Live(app.Drain()).CanGoBack);
        app.Report(engine, new NavigationCommitted(page, "https://example.org/", SameDocument: false));
        Assert.Null(Live(app.Drain()).Failure);
        Assert.Equal(new UnknownPage(Guid.Empty), Refusal(app, new LeavePageFailure(Guid.Empty)));
    }

    [Fact]
    public void NavigateResolvesInputByTheSpacesRulesAndAsksTheEngineToLoadIt() {
        var (app, engine, binding, page, _, _, _, _) = LivePage();
        using var disposal = app;
        app.Report(engine, new NavigationFailed(page, new PageFailure(NavigationError.Offline, "https://offline.example/",
            ReplacedDocument: false, "NSURLErrorDomain", -1009)));
        app.Drain();

        // Words are the Space's search, and the page shows where it is heading at once.
        var duckDuckGo = SearchCatalog.Starting(language: null, region: null).Resolving(BuiltInSearchProvider.DuckDuckGo);
        var search = duckDuckGo.Search("crest browser");
        var heading = Live(app.Send(new Navigate(page, "  crest browser ")));
        Assert.Equal((search, null, search), (heading.PendingUrl, heading.Failure, heading.Address));
        Assert.Equal(new LoadPage(page, search), binding.Commands[^1]);

        // A host is an address, and an engine without internal pages searches for one.
        app.Send(new Navigate(page, "example.org/path"));
        Assert.Equal(new LoadPage(page, "https://example.org/path"), binding.Commands[^1]);
        app.Send(new Navigate(page, "chrome://flags"));
        Assert.Equal(new LoadPage(page, duckDuckGo.Search("chrome://flags")), binding.Commands[^1]);
        app.Send(new Navigate(page, "about:blank#start"));
        Assert.Equal(new LoadPage(page, "about:blank#start"), binding.Commands[^1]);

        // Blank input, and what no page can load, are refused.
        var issued = binding.Commands.Count;
        Assert.Equal(new UnsupportedAddress(" "), Refusal(app, new Navigate(page, " ")));
        var endless = new string('a', 4097);
        Assert.Equal(new UnsupportedAddress(endless), Refusal(app, new Navigate(page, endless)));
        Assert.Equal(new UnknownPage(Guid.Empty), Refusal(app, new Navigate(Guid.Empty, "example.org")));
        Assert.Equal(issued, binding.Commands.Count);

        // A page its engine lost holds nothing to load into.
        app.Report(engine, new PageClosed(page, RestoreState: null));
        Assert.Equal(new PageNotLoadable(page), Refusal(app, new Navigate(page, "example.org")));
    }

    [Fact]
    public void ASavedTabReturnsHomeWhenItOrItsPageHasLeftIt() {
        var (app, engine, _, page, workspace, window, space, tab) = LivePage();
        using var disposal = app;
        bool Returns() => app.Query(new CanReturnToSavedAddress(workspace, window, space, tab)).ChangesPage;

        // The fixture's saved tab shows another page than the one it was saved at.
        Assert.True(Returns());
        app.Send(new ReturnToSavedAddress(workspace, space, tab));
        Assert.False(Returns());

        // Its page heading within the saved page is still home; heading elsewhere is not.
        app.Report(engine, new PageStateChanged(page, PageSnapshot.Blank with { PendingUrl = "https://example.com/#top" }));
        app.Drain();
        Assert.False(Returns());
        app.Report(engine, new PageStateChanged(page, PageSnapshot.Blank with { PendingUrl = "https://elsewhere.example/" }));
        app.Drain();
        Assert.True(Returns());
        Assert.False(app.Query(new CanReturnToSavedAddress(workspace, window, space, Guid.NewGuid())).ChangesPage);
    }

    [Fact]
    public void NavigateLoadsInternalPagesOnlyOnAnEngineThatShowsThemAndNeverInALockedSpace() {
        var session = SavedSession().Document["session"]!;
        var space = SpaceId(session["spaces"]![0]!);
        using var app = new CrestApp();
        var binding = new RecordingEngine();
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium,
            [.. EngineCapability.Required, EngineCapability.InternalPages], IsDefault: true), binding.Run);
        var workspace = TestWorkspaces.Open(app, session);
        var authority = app.Workspace(workspace);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, space, null, window));
        app.Report(engine, new PageCreated(page));

        app.Send(new Navigate(page, "chrome://flags"));
        Assert.Equal(new LoadPage(page, "chrome://flags"), binding.Commands[^1]);

        // The Space asks for authentication from now on, and this process
        // holds no grant for it.
        app.Send(new SetSpaceAccess(workspace, space, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Assert.Equal(new SpaceLocked(space), Refusal(app, new Navigate(page, "example.org")));
    }
}
