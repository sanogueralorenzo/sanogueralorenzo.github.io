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

}
