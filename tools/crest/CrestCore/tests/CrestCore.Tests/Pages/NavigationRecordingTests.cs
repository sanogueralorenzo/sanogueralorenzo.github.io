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

}
