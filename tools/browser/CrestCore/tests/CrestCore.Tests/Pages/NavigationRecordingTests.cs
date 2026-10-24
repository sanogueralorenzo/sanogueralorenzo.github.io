using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// What the core records from a page's navigations: one record per document,
/// on the tab that owns the page and in its Space's history, and nothing for a
/// failure, a locked Space or a move that stays on the page.
public sealed partial class BrowserContractsTests {
    /// A live page for the fixture tab of `session`'s first Space, or for a
    /// Quick Window or Peek request when `transient`, hosted over a workspace of
    /// `kind` opened from `session`.
    private static (CrestApp App, Engine Engine, Guid Page, Guid Workspace) NavigatingPage(JsonNode session,
        WorkspaceKind? kind = null, bool transient = false) {
        var (app, engine, _, workspace, window) = PageHost(session, kind);
        var page = Guid.NewGuid();
        var space = session["spaces"]![0]!;
        app.Send(new OpenPage(page, workspace, SpaceId(space), transient ? null : TabId(space, 0), window));
        app.Report(engine, new PageCreated(page));
        app.Drain();
        return (app, engine, page, workspace);
    }

    /// Reports a new document at `url` that finishes titled `title`, and
    /// answers the changes it caused.
    private static IReadOnlyList<Change> Browse(CrestApp app, Engine engine, Guid page, string url, string title) {
        app.Report(engine, new NavigationStarted(page, url, SameDocument: false));
        app.Report(engine, new NavigationCommitted(page, url, SameDocument: false));
        app.Report(engine, new NavigationFinished(page, url, title));
        return Own(app.Drain());
    }

    private static TabState FirstTab(NativeSessionAuthority authority) => authority.Current.Spaces[0].Tabs[0];

    private static IReadOnlyList<HistoryEntryState> History(NativeSessionAuthority authority) => authority.Current.Spaces[0].History;

    [Fact]
    public void ATabsPageRecordsEachDocumentOnceInOneRevisionWhenItFinishes() {
        var session = SavedSession().Document["session"]!;
        var (app, engine, page, workspace) = NavigatingPage(session);
        var authority = app.Workspace(workspace);
        using var disposal = app;
        var earlier = History(authority)[0];

        // The tab and the visit change together, then the record is announced.
        var changes = Browse(app, engine, page, "https://example.com/article#two", "Later title");
        Assert.Equal([typeof(TabsChanged), typeof(HistoryChanged), typeof(NavigationRecorded)], changes.Select(change => change.GetType()));
        Assert.Equal(new NavigationRecorded(page, workspace, SpaceId(session["spaces"]![0]!), FirstTab(authority).Id,
            "https://example.com/article#two"), changes[^1]);
        Assert.Equal(("https://example.com/article#two", "Later title"), (FirstTab(authority).Url, FirstTab(authority).Title));
        // A page's title never replaces a name the person gave the tab.
        Assert.Equal("My reading", FirstTab(authority).CustomTitle);
        // A fragment is the same page, so the visit joins its entry.
        Assert.Equal(earlier with { Title = "Later title", LastVisitedAt = History(authority)[0].LastVisitedAt, VisitCount = 5 },
            History(authority)[0]);

        // A second finish of the same document records nothing.
        app.Report(engine, new NavigationFinished(page, "https://example.com/article#two", "Again"));
        Assert.Empty(Own(app.Drain()));

        // A document that commits and never finishes records nothing.
        app.Report(engine, new NavigationCommitted(page, "https://example.com/unfinished", SameDocument: false));
        Assert.Empty(Own(app.Drain()));
        Assert.Equal("https://example.com/article#two", FirstTab(authority).Url);

        // A blank title is the page saying nothing, not a request to clear.
        Browse(app, engine, page, "https://example.com/untitled", "");
        Assert.Equal(("https://example.com/untitled", "Later title"), (FirstTab(authority).Url, FirstTab(authority).Title));
        Assert.Equal(("https://example.com/untitled", "example.com"), (History(authority)[0].Url, History(authority)[0].Title));
    }

    [Fact]
    public void AQuickWindowOrPeekPageRecordsOnlyAVisit() {
        var session = SavedSession().Document["session"]!;
        var (app, engine, page, workspace) = NavigatingPage(session, transient: true);
        var authority = app.Workspace(workspace);
        using var disposal = app;
        var tab = FirstTab(authority);

        var changes = Browse(app, engine, page, "https://news.example/story", "Story");
        Assert.Equal([typeof(HistoryChanged), typeof(NavigationRecorded)], changes.Select(change => change.GetType()));
        Assert.Null(Assert.IsType<NavigationRecorded>(changes[^1]).TabId);
        Assert.Equal(tab, FirstTab(authority));
        Assert.Equal(("https://news.example/story", "Story", 1), (History(authority)[0].Url, History(authority)[0].Title,
            History(authority)[0].VisitCount));

        // An address history does not keep changes nothing, and is still taken.
        var history = History(authority);
        Assert.Equal([typeof(NavigationRecorded)], Browse(app, engine, page, "crest://extensions", "Extensions")
            .Select(change => change.GetType()));
        Assert.Equal(history, History(authority));
    }

    [Fact]
    public void APageInALockedSpaceRecordsNothing() {
        var session = SavedSession().Document["session"]!;
        var (app, engine, page, workspace) = NavigatingPage(session);
        var authority = app.Workspace(workspace);
        using var disposal = app;
        // The Space asks for authentication from now on, and this process
        // holds no grant for it.
        app.Send(new SetSpaceAccess(workspace, SpaceId(session["spaces"]![0]!), SpaceAccessPolicy.DeviceOwnerAuthentication));
        var before = authority.Current;

        Assert.Empty(Browse(app, engine, page, "https://example.com/secret", "Secret"));
        Assert.Same(before, authority.Current);
    }

    [Fact]
    public void APrivateWorkspaceRecordsIntoItsOwnMemorySession() {
        var session = SavedSession().Document["session"]!.DeepClone().AsObject();
        var (app, engine, page, workspace) = NavigatingPage(session, WorkspaceKind.Private);
        var authority = app.Workspace(workspace);
        using var disposal = app;

        Assert.Contains(Browse(app, engine, page, "https://private.example/", "Private"), change => change is NavigationRecorded);
        Assert.Equal(WorkspaceKind.Private, authority.Kind);
        Assert.Equal("https://private.example/", FirstTab(authority).Url);
        Assert.Equal("https://private.example/", History(authority)[0].Url);
    }

    [Fact]
    public void AMoveWithinTheDocumentRecordsOnlyWhenItReachesAnotherPage() {
        var session = SavedSession().Document["session"]!;
        var (app, engine, page, workspace) = NavigatingPage(session);
        var authority = app.Workspace(workspace);
        using var disposal = app;
        Browse(app, engine, page, "https://app.example/inbox", "Inbox");

        void Move(string url, string title) {
            app.Report(engine, new NavigationStarted(page, url, SameDocument: true));
            app.Report(engine, new NavigationCommitted(page, url, SameDocument: true));
            app.Report(engine, new NavigationFinished(page, url, title));
        }

        // A fragment stays on the page it names.
        Move("https://app.example/inbox#message-4", "Inbox");
        Assert.Empty(Own(app.Drain()));
        Assert.Equal("https://app.example/inbox", FirstTab(authority).Url);

        // `pushState` to another page is a visit of its own, recorded once.
        Move("https://app.example/message/4", "Message 4");
        Assert.Single(Own(app.Drain()).OfType<NavigationRecorded>());
        Assert.Equal(("https://app.example/message/4", "Message 4"), (FirstTab(authority).Url, FirstTab(authority).Title));
        Assert.Equal(["https://app.example/message/4", "https://app.example/inbox"], History(authority).Take(2).Select(entry => entry.Url));
        app.Report(engine, new NavigationFinished(page, "https://app.example/message/4", "Message 4"));
        Assert.Empty(Own(app.Drain()));
    }

    [Fact]
    public void ATitleThePageGivesItsRecordedDocumentLaterNamesItsTabAndItsVisitWhileThePageSettles() {
        var (app, engine, _, clock, workspace, window, space, tab) = ResidentHost();
        var authority = app.Workspace(workspace);
        using var disposal = app;
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, space, tab, window));
        app.Report(engine, new PageCreated(page));
        void Titled(string url, string title, TimeSpan after) {
            clock.Now += after;
            app.Report(engine, new PageStateChanged(page, Showing(url, title)));
            app.Drain();
        }
        (string Tab, string Visit) Names(string url) =>
            (authority.Current.Spaces[0].Tabs.Single(shown => shown.Id == tab).Title, History(authority).First(entry => entry.Url == url).Title);

        // A page built in script names itself after it finished loading, through
        // a placeholder, and its tab and visit follow.
        Browse(app, engine, page, "https://app.example/", "");
        Assert.Equal("app.example", Names("https://app.example/").Visit);
        Titled("https://app.example/", "Loading…", TimeSpan.FromSeconds(1));
        Titled("https://app.example/", "Inbox", TimeSpan.FromSeconds(1));
        Assert.Equal(("Inbox", "Inbox"), Names("https://app.example/"));

        // Once the page settled, only its tab follows a title flashing news.
        Titled("https://app.example/", "(1) Inbox", TimeSpan.FromSeconds(10));
        Assert.Equal(("(1) Inbox", "Inbox"), Names("https://app.example/"));

        // A title shown while the page heads elsewhere names nothing.
        Titled("https://elsewhere.example/", "Elsewhere", TimeSpan.Zero);
        Assert.Equal(("(1) Inbox", "Inbox"), Names("https://app.example/"));

        // A page loaded out of sight names itself once shown, however much later.
        Browse(app, engine, page, "https://later.example/", "");
        Titled("https://later.example/", "Later", TimeSpan.FromMinutes(5));
        Assert.Equal(("Later", "Later"), Names("https://later.example/"));

        // Reloaded out of sight, it says nothing yet and keeps both names.
        Browse(app, engine, page, "https://later.example/", "");
        Assert.Equal(("Later", "Later"), Names("https://later.example/"));
    }

    [Fact]
    public void AFailedNavigationRecordsNothingAndTheNextDocumentDoes() {
        var session = SavedSession().Document["session"]!;
        var (app, engine, page, workspace) = NavigatingPage(session);
        var authority = app.Workspace(workspace);
        using var disposal = app;
        var before = authority.Current;

        app.Report(engine, new NavigationStarted(page, "https://down.example/", SameDocument: false));
        app.Report(engine, new NavigationCommitted(page, "https://down.example/", SameDocument: false));
        app.Report(engine, new NavigationFailed(page, new PageFailure(NavigationError.ConnectionLost, "https://down.example/",
            ReplacedDocument: false, "NSURLErrorDomain", -1005)));
        app.Report(engine, new NavigationFinished(page, "https://down.example/", "Error"));
        // The page shows the failure, and the session records nothing.
        Assert.Equal(NavigationError.ConnectionLost, Assert.IsType<PageChanged>(Assert.Single(Own(app.Drain()))).Page.Live.Failure?.Error);
        Assert.Same(before, authority.Current);

        Assert.Single(Browse(app, engine, page, "https://up.example/", "Up").OfType<NavigationRecorded>());
    }

    [Fact]
    public void ATabWearsItsDocumentsIconOnlyWhileItsIconFollowsThePage() {
        var session = SavedSession().Document["session"]!;
        var (app, engine, page, workspace) = NavigatingPage(session);
        var authority = app.Workspace(workspace);
        using var disposal = app;
        var tab = FirstTab(authority).Id;
        var space = authority.Current.Spaces[0].Id;
        void Choose(TabIconMode mode, string? emoji = null) => app.Send(new ChooseTabIcon(workspace, space, tab, mode, emoji, null));
        Choose(TabIconMode.Automatic);
        app.Drain();
        var accent = new TabIconAccent(0.5, 0.25, 0.125);

        // An icon found before the document is recorded waits for the record.
        app.Report(engine, new NavigationCommitted(page, "https://example.org/", SameDocument: false));
        app.Report(engine, new PageIconChanged(page, "https://example.org/", accent));
        Assert.Empty(Own(app.Drain()));
        app.Report(engine, new NavigationFinished(page, "https://example.org/", "Example"));
        Assert.Contains(new TabFaviconAssigned(workspace, tab, Adopts: true, page), Own(app.Drain()));
        Assert.Equal(("https://example.org/", accent), (FirstTab(authority).FaviconUrl, FirstTab(authority).IconAccent));

        // Once it is recorded, a new icon or theme goes straight to the tab.
        var themed = new TabIconAccent(1, 0, 0);
        app.Report(engine, new PageIconChanged(page, "https://example.org/", themed));
        Assert.Equal([typeof(TabsChanged), typeof(TabFaviconAssigned)], Own(app.Drain()).Select(change => change.GetType()));
        Assert.Equal(themed, FirstTab(authority).IconAccent);

        // A new document leaves the old one's icon behind.
        Browse(app, engine, page, "https://example.net/", "Elsewhere");
        Assert.Equal("https://example.org/", FirstTab(authority).FaviconUrl);

        // A chosen icon is never replaced by the page's.
        Choose(TabIconMode.Emoji, "📚");
        app.Drain();
        app.Report(engine, new PageIconChanged(page, "https://example.net/", accent));
        Assert.Empty(Own(app.Drain()));
        Assert.Equal("crest.emoji:📚", FirstTab(authority).Symbol);
    }

    [Fact]
    public void NavigatingANativeTabGivesItAWebAddressAndLeavesAWebPageToItsEngine() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var tab = session["spaces"]![0]!["tabs"]![0]!.AsObject();
        tab["url"] = null;
        tab["savedURL"] = null;
        tab["nativeContent"] = new JsonObject { ["kind"] = "settings" };
        using var app = new CrestApp();
        var workspace = TestWorkspaces.Open(app, session);
        var authority = app.Workspace(workspace);
        app.Drain();

        // Blank input, and input no page can load, are refused.
        Assert.Equal(new UnsupportedAddress("  "), Refusal(app, new NavigateTab(workspace, fixture.Space, fixture.Tab, "  ")));
        var endless = new string('a', 4097);
        Assert.Equal(new UnsupportedAddress(endless), Refusal(app, new NavigateTab(workspace, fixture.Space, fixture.Tab, endless)));

        // A host the person typed becomes its address.
        Assert.IsType<TabsChanged>(Assert.Single(app.Send(new NavigateTab(workspace, fixture.Space, fixture.Tab, " example.org "))));
        Assert.Null(FirstTab(authority).NativeContent);
        Assert.Equal(("https://example.org", "example.org"), (FirstTab(authority).Url, FirstTab(authority).Title));

        // A web page keeps its address until its engine reports one.
        Assert.Empty(app.Send(new NavigateTab(workspace, fixture.Space, fixture.Tab, "https://example.net/")));
        Assert.Equal(new UnknownSpace(fixture.Tab), Refusal(app, new NavigateTab(workspace, fixture.Tab, fixture.Tab, "https://a.example/")));
        var gone = Guid.NewGuid();
        Assert.Equal(new UnknownTab(gone), Refusal(app, new NavigateTab(workspace, fixture.Space, gone, "https://example.net/")));
    }
}
