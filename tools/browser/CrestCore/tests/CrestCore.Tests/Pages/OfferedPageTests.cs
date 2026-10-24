using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Pages an engine opens by itself, links it asks the core about, and links it
/// stages for a Peek's first load: the core decides where an offered page
/// goes and refuses what a Space may not take, answers what a link does by
/// the link rules, and routes a staged link only to a page of its source's
/// engine and profile.
public sealed partial class BrowserContractsTests {
    /// A current tab showing `url`, opened and shown in `window`, with a live
    /// page of its own there.
    private static (Guid Tab, Guid Page) LiveTab(CrestApp app, Engine engine, Guid workspace, Guid window, Guid space,
        string url = "https://source.example/") {
        var (tab, page) = (Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenTab(workspace, window, space, tab, new TabContent(url, View: null, Title: null),
            TabPlacement.Current, AfterTabId: null, Shows: true));
        app.Send(new OpenPage(page, workspace, space, tab, window));
        app.Report(engine, new PageCreated(page));
        return (tab, page);
    }

    /// The current tabs of a Space, in order.
    private static List<TabState> CurrentTabs(CrestApp app, Guid workspace, Guid space) =>
        [.. app.Workspace(workspace).Current.Spaces.Single(held => held.Id == space).Tabs.Where(tab => tab.Placement == TabPlacement.Current)];

    /// The tab `window` shows in `space`, as the last window change says.
    private static Guid? ShownTab(IReadOnlyList<Change> changes, Guid window, Guid space) =>
        changes.OfType<WindowChanged>().Last(change => change.Window.Id == window).Window.ShownTabs
            .SingleOrDefault(shown => shown.SpaceId == space)?.TabId;

    [Fact]
    public void AnOfferedPageFromATabOpensInATabAfterItsOwnThatOwnsThePage() {
        var session = TwoSpaceSession();
        var (space, profile) = (SpaceId(session["spaces"]![0]!), ProfileId(session["spaces"]![0]!));
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (sourceTab, sourcePage) = LiveTab(app, engine, workspace, window, space);
        LiveTab(app, engine, workspace, window, space, "https://following.example/");
        app.Send(new ShowTab(window, space, sourceTab));
        app.Drain();

        var offer = Guid.NewGuid();
        app.Report(engine, new PageOffered(offer, profile, sourcePage, window, SpaceId: null, "https://popup.example/", Foreground: true));

        var changes = app.Drain();
        var adopted = Assert.Single(changes.OfType<OfferedPageAdopted>());
        var tabs = CurrentTabs(app, workspace, space);
        Assert.Equal(tabs.FindIndex(tab => tab.Id == sourceTab) + 1, tabs.FindIndex(tab => tab.Id == adopted.TabId));
        Assert.Equal("https://popup.example/", tabs.Single(tab => tab.Id == adopted.TabId).Url);
        Assert.Equal((workspace, window, space, true), (adopted.WorkspaceId, adopted.WindowId, adopted.SpaceId, adopted.Shows));
        Assert.Equal(adopted.TabId, ShownTab(changes, window, space));
        var opened = Assert.Single(changes.OfType<PageOpened>()).Page;
        Assert.Equal((adopted.PageId, (Guid?)adopted.TabId, PagePhase.Opening), (opened.Id, opened.TabId, opened.Phase));
        Assert.Equal(new AdoptOfferedPage(adopted.PageId, offer, profile, IsPrivate: false, window), binding.Commands[^1]);

        // The engine created the page it adopted, and the tab keeps it.
        app.Report(engine, new PageCreated(adopted.PageId));
        Assert.Equal(PagePhase.Live, Assert.IsType<PageChanged>(Assert.Single(app.Drain())).Page.Phase);
        Assert.Equal(new TabAlreadyHasPage(adopted.TabId, adopted.PageId),
            Refusal(app, new OpenPage(Guid.NewGuid(), workspace, space, adopted.TabId, window)));

        // A page the engine opened behind opens its tab without showing it.
        app.Report(engine, new PageOffered(Guid.NewGuid(), profile, sourcePage, window, SpaceId: null, "https://behind.example/",
            Foreground: false));
        var behind = app.Drain();
        Assert.False(Assert.Single(behind.OfType<OfferedPageAdopted>()).Shows);
        Assert.All(behind.OfType<WindowChanged>().Where(change => change.Window.Id == window),
            change => Assert.Equal(adopted.TabId, change.Window.ShownTabs.Single(shown => shown.SpaceId == space).TabId));
    }

    [Fact]
    public void AWindowAPageAsksForOpensAsAQuickWindowOfItsOpenersSpaceAndNeverAsATab() {
        var session = TwoSpaceSession();
        var (space, profile) = (SpaceId(session["spaces"]![0]!), ProfileId(session["spaces"]![0]!));
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (_, source) = LiveTab(app, engine, workspace, window, space);
        app.Drain();
        int tabs = CurrentTabs(app, workspace, space).Count;

        // The engine made the page a window of its own, as it does for a sign-in popup.
        var offer = Guid.NewGuid();
        const string signIn = "https://accounts.example/sign-in";
        app.Report(engine, new PageOffered(offer, profile, source, WindowId: null, space, signIn, Foreground: true));
        var changes = app.Drain();
        var adopted = Assert.Single(changes.OfType<OfferedWindowAdopted>());
        Assert.Equal((source, workspace, window, space, signIn),
            (adopted.SourcePageId, adopted.WorkspaceId, adopted.WindowId, adopted.SpaceId, adopted.Url));
        Assert.Empty(changes.OfType<OfferedPageAdopted>());
        Assert.Equal(tabs, CurrentTabs(app, workspace, space).Count);
        var opened = Assert.Single(changes.OfType<PageOpened>()).Page;
        Assert.Equal((adopted.PageId, (Guid?)null, EngineKind.WebKit), (opened.Id, opened.TabId, opened.Engine));
        Assert.Equal(new AdoptOfferedPage(adopted.PageId, offer, profile, IsPrivate: false, window), binding.Commands[^1]);

        // A window the Quick Window's page asks for opens a Quick Window of its own, and nothing loads in the first.
        app.Report(engine, new PageCreated(adopted.PageId));
        app.Drain();
        var nested = Guid.NewGuid();
        app.Report(engine, new PageOffered(nested, profile, adopted.PageId, WindowId: null, space, signIn + "/next", Foreground: true));
        Assert.Single(app.Drain().OfType<OfferedWindowAdopted>());
        Assert.Equal(nested, Assert.IsType<AdoptOfferedPage>(binding.Commands[^1]).OfferId);
        Assert.DoesNotContain(binding.Commands, command => command is LoadPage load && load.PageId == adopted.PageId);
        Assert.Equal(tabs, CurrentTabs(app, workspace, space).Count);
    }

    [Fact]
    public void AnOfferedPageNoPageOpenedJoinsItsWindowInTheSpaceReservedForItOrTheOneTheWindowShows() {
        var session = TwoSpaceSession();
        var (first, second) = (session["spaces"]![0]!, session["spaces"]![1]!);
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (shownTab, _) = LiveTab(app, engine, workspace, window, SpaceId(first));

        // An engine window reserved for a Space opens its tab there.
        app.Report(engine, new PageOffered(Guid.NewGuid(), ProfileId(second), SourcePageId: null, window, SpaceId(second),
            "https://extension.example/", Foreground: true));
        var reserved = Assert.Single(app.Drain().OfType<OfferedPageAdopted>());
        Assert.Equal(SpaceId(second), reserved.SpaceId);

        // Without a reservation, the page opens after the tab the window shows
        // in the Space it shows.
        app.Send(new ShowTab(window, SpaceId(first), shownTab));
        app.Drain();
        app.Report(engine, new PageOffered(Guid.NewGuid(), ProfileId(first), SourcePageId: null, window, SpaceId: null,
            "https://opened.example/", Foreground: false));
        var joined = Assert.Single(app.Drain().OfType<OfferedPageAdopted>());
        var tabs = CurrentTabs(app, workspace, SpaceId(first));
        Assert.Equal(tabs.FindIndex(tab => tab.Id == shownTab) + 1, tabs.FindIndex(tab => tab.Id == joined.TabId));
        Assert.IsType<AdoptOfferedPage>(binding.Commands[^1]);
    }

    [Fact]
    public void NoSpaceTakesAnOfferedPageItMayNotHost() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var locked = Identity(session);
        var open = session["spaces"]![1]!;
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        int tabs = app.Workspace(workspace).Current.Spaces.Sum(space => space.Tabs.Count);
        void Refused(PageOffered offer) {
            app.Report(engine, offer);
            Assert.Equal(new RejectOfferedPage(offer.OfferId), binding.Commands[^1]);
            Assert.Empty(app.Drain().OfType<OfferedPageAdopted>());
            Assert.Equal(tabs, app.Workspace(workspace).Current.Spaces.Sum(space => space.Tabs.Count));
        }

        // A locked Space, one of another profile, and a window that is not
        // open or not named take nothing.
        Refused(new PageOffered(Guid.NewGuid(), locked.Profile, null, window, locked.Space, "https://locked.example/", true));
        Refused(new PageOffered(Guid.NewGuid(), ProfileId(open), null, window, locked.Space, "https://other.example/", true));
        Refused(new PageOffered(Guid.NewGuid(), ProfileId(open), null, Guid.NewGuid(), SpaceId(open), "https://closed.example/", true));
        Refused(new PageOffered(Guid.NewGuid(), ProfileId(open), null, WindowId: null, SpaceId(open), "https://nowhere.example/", true));

        // Unlocked, the Space takes it.
        Unlock(app.Send, workspace, locked.Space);
        app.Report(engine, new PageOffered(Guid.NewGuid(), locked.Profile, null, window, locked.Space, "https://unlocked.example/", true));
        Assert.Single(app.Drain().OfType<OfferedPageAdopted>());
        tabs++;

        // A Space being deleted takes nothing.
        app.Send(new BeginDeletingSpace(workspace, window, SpaceId(open), Guid.NewGuid()));
        app.Drain();
        Refused(new PageOffered(Guid.NewGuid(), ProfileId(open), null, window, SpaceId(open), "https://deleting.example/", true));
    }

    [Fact]
    public void APageAQuickWindowOrPeekOpensLoadsInItInsteadOfATab() {
        var session = TwoSpaceSession();
        var (space, profile) = (SpaceId(session["spaces"]![0]!), ProfileId(session["spaces"]![0]!));
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var peek = Guid.NewGuid();
        app.Send(new OpenPage(peek, workspace, space, null, window, TransientPresentation.Peek));
        app.Report(engine, new PageCreated(peek));
        app.Drain();
        int tabs = CurrentTabs(app, workspace, space).Count;

        var offer = Guid.NewGuid();
        app.Report(engine, new PageOffered(offer, profile, peek, window, SpaceId: null, "https://sign-in.example/", Foreground: true));
        Assert.Equal([new RejectOfferedPage(offer), new LoadPage(peek, "https://sign-in.example/")], binding.Commands[^2..]);
        Assert.Equal("https://sign-in.example/", Assert.IsType<PageChanged>(Assert.Single(app.Drain())).Page.Live.PendingUrl);
        Assert.Equal(tabs, CurrentTabs(app, workspace, space).Count);

        // The empty document at a fragment the opener named is an address, and
        // loads there too; a page with no address yet loads nothing.
        var fragment = Guid.NewGuid();
        app.Report(engine, new PageOffered(fragment, profile, peek, window, SpaceId: null, "about:blank#done", Foreground: true));
        Assert.Equal([new RejectOfferedPage(fragment), new LoadPage(peek, "about:blank#done")], binding.Commands[^2..]);
        app.Drain();
        var blank = Guid.NewGuid();
        app.Report(engine, new PageOffered(blank, profile, peek, window, SpaceId: null, "about:blank", Foreground: true));
        Assert.Equal(new RejectOfferedPage(blank), binding.Commands[^1]);
        Assert.Empty(app.Drain());
    }

    [Fact]
    public void AnEngineAsksWhatALinkDoesAndTheLinkRulesAnswerForItsOwnPagesAlone() {
        var session = TwoSpaceSession();
        var space = SpaceId(session["spaces"]![0]!);
        var (app, engine, _, workspace, window) = PageHost(session);
        using var disposal = app;
        var (_, page) = LiveTab(app, engine, workspace, window, space);
        var other = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: false), _ => { });

        foreach (var gesture in new[] {
                     new LinkGesture(UserActivated: true, TopLevel: true, ShortcutModifiers.None, MiddleClick: false),
                     new LinkGesture(UserActivated: true, TopLevel: true, ShortcutModifiers.Command, MiddleClick: false),
                     new LinkGesture(UserActivated: true, TopLevel: true, ShortcutModifiers.Option, MiddleClick: false),
                     new LinkGesture(UserActivated: true, TopLevel: true, ShortcutModifiers.None, MiddleClick: true)
                 }) {
            var asked = app.Ask(engine, new LinkActivation(page, "https://elsewhere.example/", gesture));
            Assert.Equal(app.Query(new LinkNavigation(page, "https://elsewhere.example/", gesture)), asked);
            // Another engine, or a page the core does not host, loads the link itself.
            Assert.Equal(LinkNavigationDecision.Navigate, app.Ask(other, new LinkActivation(page, "https://elsewhere.example/", gesture)).Decision);
            Assert.Equal(LinkNavigationDecision.Navigate,
                app.Ask(engine, new LinkActivation(Guid.NewGuid(), "https://elsewhere.example/", gesture with { Modifiers = ShortcutModifiers.Option })).Decision);
        }
        Assert.Equal(LinkNavigationDecision.PeekModifier, app.Ask(engine, new LinkActivation(page, "https://elsewhere.example/",
            new LinkGesture(UserActivated: true, TopLevel: true, ShortcutModifiers.Option, MiddleClick: false))).Decision);
    }

    [Fact]
    public void APlainClickLeavingAPinnedOrSavedTabsSiteOpensPeekAndAnOpenTabLoadsItInPlace() {
        var session = TwoSpaceSession();
        var space = SpaceId(session["spaces"]![0]!);
        var (app, engine, _, workspace, window) = PageHost(session);
        using var disposal = app;
        var click = new LinkGesture(UserActivated: true, TopLevel: true, ShortcutModifiers.None, MiddleClick: false);

        foreach (var (placement, leaving) in new[] {
                     (TabPlacement.Pinned, LinkNavigationDecision.PeekSavedSite),
                     (TabPlacement.Saved, LinkNavigationDecision.PeekSavedSite),
                     (TabPlacement.Current, LinkNavigationDecision.Navigate)
                 }) {
            var (tab, page) = (Guid.NewGuid(), Guid.NewGuid());
            app.Send(new OpenTab(workspace, window, space, tab, new TabContent("https://www.home.example/start", View: null, Title: null),
                placement, AfterTabId: null, Shows: true));
            app.Send(new OpenPage(page, workspace, space, tab, window));
            app.Report(engine, new PageCreated(page));

            Assert.Equal(leaving, app.Ask(engine, new LinkActivation(page, "https://elsewhere.example/", click)).Decision);
            // A link that stays on the tab's site, with or without its www, loads in the tab.
            Assert.Equal(LinkNavigationDecision.Navigate, app.Ask(engine, new LinkActivation(page, "https://home.example/next", click)).Decision);
        }
    }

    [Fact]
    public void AStagedLinkLoadsOnlyInANewPageOfItsSourcesEngineAndProfile() {
        var session = TwoSpaceSession();
        var (first, second) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (_, source) = LiveTab(app, engine, workspace, window, first);
        var (peek, elsewhere) = (Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenPage(peek, workspace, first, null, window, TransientPresentation.Peek));
        app.Send(new OpenPage(elsewhere, workspace, second, null, window, TransientPresentation.Peek));
        var link = Guid.NewGuid();

        app.Send(new StageLink(peek, source, link, "https://followed.example/"));
        Assert.Equal(new StageNavigation(peek, link, "https://followed.example/"), binding.Commands[^1]);
        Assert.Equal(new StagedLinkElsewhere(elsewhere, source),
            Refusal(app, new StageLink(elsewhere, source, link, "https://followed.example/")));
        var missing = Guid.NewGuid();
        Assert.Equal(new UnknownPage(missing), Refusal(app, new StageLink(missing, source, link, "https://followed.example/")));

        // An engine that creates its page at once, as WebKit does, stages the
        // link in a page that has loaded nothing yet; once the page heads
        // anywhere, it has had its first load.
        app.Report(engine, new PageCreated(peek));
        app.Send(new StageLink(peek, source, link, "https://followed.example/"));
        Assert.Equal(new StageNavigation(peek, link, "https://followed.example/"), binding.Commands[^1]);
        app.Send(new Navigate(peek, "https://followed.example/"));
        Assert.Equal(new StagedLinkElsewhere(peek, source), Refusal(app, new StageLink(peek, source, link, "https://followed.example/")));

        // A link that no longer applies leaves the page where it was.
        app.Drain();
        app.Report(engine, new StagedLinkUnavailable(peek));
        var live = Assert.IsType<PageChanged>(Assert.Single(app.Drain())).Page.Live;
        Assert.Equal((null, false), (live.PendingUrl, live.IsLoading));

        // A link no page loads is forgotten by its source's engine; a source
        // that is gone took its links with it.
        int delivered = binding.Commands.Count;
        app.Send(new DiscardStagedLink(source, link));
        Assert.Equal(new DropStagedLink(link), binding.Commands[^1]);
        app.Send(new DiscardStagedLink(Guid.NewGuid(), link));
        Assert.Equal(delivered + 1, binding.Commands.Count);
    }
}
