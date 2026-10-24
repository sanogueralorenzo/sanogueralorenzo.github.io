using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Link preferences are device state: the device store keeps them beside the
/// session, carried once from the document an installed release kept. A link
/// another app hands a window never opens a locked Space, whatever preference
/// names it, and a link followed from a page goes where its tab, its Peek and
/// the preferences send it.
public sealed partial class BrowserContractsTests {
    private static LinkPreferences Links(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<LinkPreferencesChanged>()).Preferences;

    [Fact]
    public void TheLinkPreferencesAnInstalledReleaseKeptAreAdoptedOnceAndEveryChangeSurvivesARelaunch() {
        using var directory = new StorageDirectory();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid(), route = Guid.NewGuid(), added = Guid.NewGuid();
        // The document as the release's encoder wrote it: identities wrapped or
        // bare, a modifier this build does not know, a repeated route identity,
        // a route that does not read, and a key the release had not written yet.
        string document = $$$"""
            {"externalLinkDestination":"chosenSpace","externalLinkSpaceID":{"rawValue":"{{{work}}}"},
            "focusesNewTabsOpenedFromLinks":true,"automaticallyOpensPeek":false,"peekClickModifier":"hyper",
            "quickWindowArchivePolicy":"after24Hours","remembersQuickWindowSpaceBySite":true,
            "routes":[
                {"id":"{{{route}}}","isEnabled":false,"match":"exact","pattern":"example.com","destinationSpaceID":{"rawValue":"{{{personal}}}"}},
                {"id":"{{{route}}}","isEnabled":true,"match":"contains","pattern":"again","destinationSpaceID":"{{{work}}}"},
                {"id":"not-an-identity","isEnabled":true,"match":"contains","pattern":"x","destinationSpaceID":"{{{work}}}"}],
            "rememberedQuickWindowSpacesBySite":{"example.org":"{{{personal}}}"}}
            """;
        var expected = LinkPreferences.Default with {
            Destination = ExternalLinkDestination.ChosenSpace,
            DestinationSpaceId = work,
            FocusesNewTabs = true,
            OpensPeekAutomatically = false,
            ArchivePolicy = QuickWindowArchivePolicy.After24Hours,
            Routes = [new(route, false, LinkRouteMatch.Exact, "example.com", personal)],
            RememberedSites = [new("example.org", personal)]
        };
        LinkPreferences edited;
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            Assert.Equal(expected, Links(app.Send(new AdoptLinkPreferences(Encoding.UTF8.GetBytes(document)))));
            // A later adoption carries nothing more and publishes what the store holds.
            Assert.Equal(expected, Links(app.Send(new AdoptLinkPreferences(Encoding.UTF8.GetBytes("""{"dragsLinksToPeek":false}""")))));

            app.Send(new AddLinkRoute(added, work));
            app.Send(new EditLinkRoute(added, IsEnabled: null, Match: null, Pattern: "news", DestinationSpaceId: null));
            app.Send(new MoveLinkRoute(added, -1));
            app.Send(new SetLinkBehavior(LinkBehavior.DragsLinksToPeek, false));
            app.Send(new ChoosePeekModifier(LinkPeekModifier.Command));
            edited = Links(app.Send(new RememberQuickWindowSpace("https://www.Example.net/a", work)));
            Assert.Equal([added, route], edited.Routes.Select(link => link.Id));
            Assert.Equal(new RememberedSite("example.net", work), edited.RememberedSites[^1]);
            Assert.Equal(new LinkRouteExists(added), Assert.Throws<Rejected>(() => app.Send(new AddLinkRoute(added, work))).Rejection);
            Assert.Empty(app.Send(new MoveLinkRoute(added, -1)).OfType<LinkPreferencesChanged>());
            // An edit of a route another edit removed changes nothing else.
            var removed = Guid.NewGuid();
            app.Send(new AddLinkRoute(removed, personal));
            app.Send(new RemoveLinkRoute(removed));
            Assert.Equal(new UnknownLinkRoute(removed), Assert.Throws<Rejected>(() =>
                app.Send(new EditLinkRoute(removed, IsEnabled: false, Match: null, Pattern: null, DestinationSpaceId: null))).Rejection);
        }

        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        Assert.Equal(edited, Links(relaunched.Send(new AdoptLinkPreferences(Encoding.UTF8.GetBytes(document)))));
    }

    [Fact]
    public void ALinkFromAnotherAppNeverOpensALockedSpaceWhateverNamesIt() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var (app, _, _, workspace, window) = PageHost(session);
        using var disposal = app;
        var locked = Identity(session).Space;
        var open = SpaceId(session["spaces"]![1]!);
        app.Send(new ShowSpace(window, open));
        ExternalLinkPlacement Route(string url) => app.Query(new RouteExternalLink([window], url));
        var substituted = new ExternalLinkPlacement(open, OpensQuickWindow: true, SubstitutesForLockedSpace: true, window, OpensWindow: false);

        // A route, the chosen Space and a remembered site each name the locked Space.
        var route = Guid.NewGuid();
        app.Send(new AddLinkRoute(route, locked));
        app.Send(new EditLinkRoute(route, IsEnabled: null, Match: null, Pattern: "example.com", DestinationSpaceId: null));
        Assert.Equal(substituted, Route("https://example.com/a"));
        app.Send(new ChooseExternalLinkDestination(ExternalLinkDestination.ChosenSpace, locked));
        Assert.Equal(substituted, Route("https://example.org/"));
        app.Send(new ChooseExternalLinkDestination(ExternalLinkDestination.QuickWindow, SpaceId: null));
        app.Send(new RememberQuickWindowSpace("https://example.org/", locked));
        Assert.Equal(substituted, Route("https://example.org/b"));

        // Once unlocked, each opens where it names.
        TestGrants.Unlock(app.Send, workspace, locked);
        Assert.Equal(new ExternalLinkPlacement(locked, false, false, window, false), Route("https://example.com/a"));
        Assert.Equal(new ExternalLinkPlacement(locked, true, false, window, false), Route("https://example.org/b"));

        // With every Space locked, the link opens nowhere.
        app.Send(new LockSpace(locked));
        app.Send(new SetSpaceAccess(workspace, open, SpaceAccessPolicy.DeviceOwnerAuthentication));
        Assert.Equal(new ExternalLinkPlacement(null, false, false, null, false), Route("https://example.com/a"));
    }

    [Fact]
    public void ALinkOrDocumentFromAnotherAppGoesToTheFrontWindowOverThePersonsSpacesOrOpensOne() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var (first, second) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
        Guid back = Guid.NewGuid(), front = Guid.NewGuid(), privateWindow = Guid.NewGuid();
        app.Send(new OpenWindow(back, workspace, Saved: true, null, first, [], RestoresTabs: true));
        app.Send(new OpenWindow(front, workspace, Saved: true, null, second, [], RestoresTabs: true));
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)));
        app.Send(new OpenWindow(privateWindow, privateWorkspace, Saved: false, null, null, [], RestoresTabs: true));
        app.Send(new ChooseExternalLinkDestination(ExternalLinkDestination.MostRecentSpace, SpaceId: null));
        ExternalLinkPlacement Route(params Guid[] stacked) => app.Query(new RouteExternalLink(stacked, "https://example.com/"));
        LocalDocumentPlacement Document(params Guid[] stacked) => app.Query(new RouteLocalDocument(stacked));

        // A link or a document goes to the frontmost window over the person's
        // own Spaces, never a private one in front of it, on the Space it shows.
        Assert.Equal(new ExternalLinkPlacement(second, false, false, front, OpensWindow: false), Route(privateWindow, front, back));
        Assert.Equal(new ExternalLinkPlacement(first, false, false, back, OpensWindow: false), Route(back, front));
        Assert.Equal(new LocalDocumentPlacement(front, second, OpensWindow: false), Document(privateWindow, front, back));

        // With none of them open, each goes where it would with one: to the
        // window used last, which opens on what it showed, or a Quick Window alone.
        app.Send(new CloseWindow(front));
        app.Send(new CloseWindow(back));
        Assert.Equal(new ExternalLinkPlacement(second, false, false, front, OpensWindow: true), Route(privateWindow));
        Assert.Equal(new LocalDocumentPlacement(front, second, OpensWindow: true), Document());
        app.Send(new ChooseExternalLinkDestination(ExternalLinkDestination.QuickWindow, SpaceId: null));
        Assert.Equal(new ExternalLinkPlacement(second, true, false, null, OpensWindow: false), Route(privateWindow));
    }

    [Fact]
    public void AnExactRouteWithoutASchemeTakesTheAddressItNamesOnEitherWebScheme() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var (shown, routed) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
        Guid window = Guid.NewGuid(), route = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: true, null, shown, [], RestoresTabs: true));
        app.Send(new AddLinkRoute(route, routed));
        app.Send(new EditLinkRoute(route, IsEnabled: null, LinkRouteMatch.Exact, Pattern: null, DestinationSpaceId: null));
        app.Send(new EditLinkRoute(route, IsEnabled: null, Match: null, Pattern: "Docs.Google.com", DestinationSpaceId: null));
        Guid? Opens(string url) => app.Query(new RouteExternalLink([window], url)).SpaceId;

        // A bare host is its site's root address, with or without the slash, on either scheme.
        Assert.Equal(routed, Opens("https://docs.google.com/"));
        Assert.Equal(routed, Opens("http://docs.google.com"));
        Assert.Equal(routed, Opens("https://docs.google.com/#top"));
        // Another page at the site, a query or another port is another address.
        Assert.Equal(shown, Opens("https://docs.google.com/document/d/1"));
        Assert.Equal(shown, Opens("https://docs.google.com/?usp=sharing"));
        Assert.Equal(shown, Opens("https://docs.google.com:8443/"));

        // A port the pattern spells is read with the link's own scheme, so
        // 443 is https's root address and not http's.
        app.Send(new EditLinkRoute(route, IsEnabled: null, Match: null, Pattern: "docs.google.com:443", DestinationSpaceId: null));
        Assert.Equal(routed, Opens("https://docs.google.com/"));
        Assert.Equal(shown, Opens("http://docs.google.com/"));

        // A pattern spelled with its scheme still takes only that spelling.
        app.Send(new EditLinkRoute(route, IsEnabled: null, Match: null, Pattern: "https://docs.google.com/document", DestinationSpaceId: null));
        Assert.Equal(routed, Opens("https://docs.google.com/document"));
        Assert.Equal(shown, Opens("http://docs.google.com/document"));
    }

    [Fact]
    public void ALinkFollowedFromAPageGoesWhereItsTabItsPeekAndThePreferencesSendIt() {
        var (document, space, tab) = SavedSession();
        var (app, _, _, workspace, window) = PageHost(document["session"]!);
        using var disposal = app;
        Guid saved = Guid.NewGuid(), peek = Guid.NewGuid(), quick = Guid.NewGuid();
        app.Send(new OpenPage(saved, workspace, space, tab, window));
        app.Send(new OpenPage(peek, workspace, space, null, window, TransientPresentation.Peek));
        app.Send(new OpenPage(quick, workspace, space, null, window, TransientPresentation.QuickWindow));
        LinkNavigationDecision Follow(Guid page, string url, ShortcutModifiers held = ShortcutModifiers.None) =>
            app.Query(new LinkNavigation(page, url, new LinkGesture(UserActivated: true, TopLevel: true, held, MiddleClick: false)))
                .Decision;

        // A saved tab keeps its site: a link to another opens in Peek, until the person turns that off.
        Assert.Equal(LinkNavigationDecision.PeekSavedSite, Follow(saved, "https://webkit.org/"));
        Assert.Equal(LinkNavigationDecision.Navigate, Follow(saved, "https://example.com/other"));
        app.Send(new SetLinkBehavior(LinkBehavior.OpensPeekAutomatically, false));
        Assert.Equal(LinkNavigationDecision.Navigate, Follow(saved, "https://webkit.org/"));

        // The chosen key opens Peek and the other a new tab, which a Peek brings to the front.
        Assert.Equal(LinkNavigationDecision.PeekModifier, Follow(saved, "https://webkit.org/", ShortcutModifiers.Option));
        app.Send(new ChoosePeekModifier(LinkPeekModifier.Command));
        Assert.Equal(LinkNavigationDecision.BackgroundTab, Follow(saved, "https://webkit.org/", ShortcutModifiers.Option));
        Assert.Equal(LinkNavigationDecision.ForegroundTab, Follow(peek, "https://webkit.org/", ShortcutModifiers.Option));
        Assert.Equal(LinkNavigationDecision.BackgroundTab, Follow(quick, "https://webkit.org/", ShortcutModifiers.Option));
        // A page with no tab never opens a Peek of its own.
        Assert.Equal(LinkNavigationDecision.Navigate, Follow(peek, "https://webkit.org/", ShortcutModifiers.Command));

        // A window a page opens comes to the front unless the new-tab gesture asks otherwise.
        bool Selects(ShortcutModifiers held, bool middle = false) =>
            app.Query(new OpenedWindowSelection(new LinkGesture(UserActivated: false, TopLevel: true, held, middle))).Selects;
        Assert.True(Selects(ShortcutModifiers.None));
        Assert.False(Selects(ShortcutModifiers.Option));
        Assert.False(Selects(ShortcutModifiers.None, middle: true));
        Assert.True(Selects(ShortcutModifiers.Option | ShortcutModifiers.Shift));
        Assert.True(Selects(ShortcutModifiers.Command));
        app.Send(new SetLinkBehavior(LinkBehavior.FocusesNewTabs, true));
        Assert.True(Selects(ShortcutModifiers.Option));
        Assert.False(Selects(ShortcutModifiers.Option | ShortcutModifiers.Shift));
    }
}
