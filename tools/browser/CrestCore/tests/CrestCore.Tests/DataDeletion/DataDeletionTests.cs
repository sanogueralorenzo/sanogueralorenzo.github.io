using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Erasing what the engines keep for a profile: every registered engine is
/// asked, started or not, a deletion ends only once each has answered, and a
/// Space's deletion finishes only after this run erased its profile's data.
public sealed partial class BrowserContractsTests {
    /// Registers WebKit as the default engine and Chromium beside it, neither
    /// showing a page, each recording what the core asks of it.
    private static (Engine WebKit, RecordingEngine WebKitBinding, Engine Chromium, RecordingEngine ChromiumBinding) IdleEngines(
        CrestApp app) {
        var webKitBinding = new RecordingEngine();
        var chromiumBinding = new RecordingEngine();
        var webKit = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true),
            webKitBinding.Run);
        var chromium = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: false),
            chromiumBinding.Run);
        return (webKit, webKitBinding, chromium, chromiumBinding);
    }

    [Fact]
    public void EveryRegisteredEngineErasesAProfileEvenOneThatShowsNoPageAndTheDeletionEndsWithTheLastAnswer() {
        using var app = new CrestApp();
        var (webKit, webKitBinding, chromium, chromiumBinding) = IdleEngines(app);
        var profile = Guid.NewGuid();
        var request = Guid.NewGuid();

        Assert.Empty(app.Send(new DeleteProfileData(request, profile, Ephemeral: false)).OfType<DataDeleted>());
        var toWebKit = Assert.IsType<EraseProfileData>(Assert.Single(webKitBinding.Commands));
        var toChromium = Assert.IsType<EraseProfileData>(Assert.Single(chromiumBinding.Commands));
        Assert.Equal((profile, false), (toWebKit.ProfileId, toWebKit.Ephemeral));

        // An answer from the wrong engine counts for nothing.
        app.Report(chromium, new DataErased(toWebKit.ErasureId, Erased: true));
        app.Report(webKit, new DataErased(toWebKit.ErasureId, Erased: true));
        Assert.Empty(app.Drain().OfType<DataDeleted>());
        // One engine that could not erase everything leaves the profile not deleted.
        app.Report(chromium, new DataErased(toChromium.ErasureId, Erased: false));
        Assert.Equal([new DataDeleted(request, Deleted: false)], app.Drain().OfType<DataDeleted>());

        // A site's data goes the same way, by its host.
        var clearing = Guid.NewGuid();
        app.Send(new DeleteSiteData(clearing, profile, Ephemeral: false, "Example.COM"));
        var site = Assert.IsType<EraseSiteData>(webKitBinding.Commands[^1]);
        Assert.Equal((profile, "example.com"), (site.ProfileId, site.Host));
        app.Report(webKit, new DataErased(site.ErasureId, Erased: true));
        app.Report(chromium, new DataErased(Assert.IsType<EraseSiteData>(chromiumBinding.Commands[^1]).ErasureId, Erased: true));
        Assert.Equal([new DataDeleted(clearing, Deleted: true)], app.Drain().OfType<DataDeleted>());
        Assert.IsType<InvalidSiteHost>(Assert.Throws<Rejected>(() =>
            app.Send(new DeleteSiteData(Guid.NewGuid(), profile, Ephemeral: false, "  "))).Rejection);
    }

    [Fact]
    public void ASpaceDeletionFinishesOnlyOnceItsProfileIsErasedAndARelaunchErasesItAgain() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        var second = document["spaces"]![0]!.DeepClone().AsObject();
        second["id"] = SwiftId(Guid.NewGuid()); second["profile"]!["id"] = Guid.NewGuid().ToString();
        second["tabs"] = new JsonArray(); second["folders"] = new JsonArray(); second["history"] = new JsonArray();
        document["spaces"]!.AsArray().Add(second);
        var deleting = SpaceId(second);
        var profile = Guid.Parse(second["profile"]!["id"]!.GetValue<string>());
        var operation = Guid.NewGuid();

        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var answered = app.Send(Adoption(document));
            var (workspace, opened) = TestWorkspaces.OpenStored(app);
            DrainLaunch(app, [.. answered, .. opened]);
            var (webKit, webKitBinding, chromium, chromiumBinding) = IdleEngines(app);
            app.Send(new BeginDeletingSpace(workspace, Guid.NewGuid(), deleting, operation));
            Assert.Equal(new SpaceDataNotErased(deleting), Assert.Throws<Rejected>(() =>
                app.Send(new FinishDeletingSpace(workspace, Guid.NewGuid(), deleting, operation))).Rejection);

            // A quit waits while the engines erase the profile. One engine
            // could not: the Space stays being deleted, and waits to be tried
            // again, which a quit no longer waits for.
            app.Send(new DeleteProfileData(Guid.NewGuid(), profile, Ephemeral: false));
            Assert.Equal([deleting], Assert.IsType<SpaceDeletionUnderway>(Refusal(app, new PrepareToQuit(Guid.NewGuid()))).SpaceIds);
            app.Report(webKit, new DataErased(Assert.IsType<EraseProfileData>(webKitBinding.Commands[^1]).ErasureId, Erased: true));
            app.Report(chromium, new DataErased(Assert.IsType<EraseProfileData>(chromiumBinding.Commands[^1]).ErasureId, Erased: false));
            Assert.Equal(new SpaceDataNotErased(deleting), Assert.Throws<Rejected>(() =>
                app.Send(new FinishDeletingSpace(workspace, Guid.NewGuid(), deleting, operation))).Rejection);
            Assert.Contains(app.Send(new PrepareToQuit(Guid.NewGuid())), change => change is CloseReady { Allowed: true });
        }

        // After a relaunch the deletion resumes, and must erase the profile again.
        using var relaunched = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var (again, _) = TestWorkspaces.OpenStored(relaunched);
        Assert.Contains(relaunched.Workspace(again).Current.SpaceDeletions, pending => pending.SpaceId == deleting);
        var engines = IdleEngines(relaunched);
        Assert.Equal(new SpaceDataNotErased(deleting), Assert.Throws<Rejected>(() =>
            relaunched.Send(new FinishDeletingSpace(again, Guid.NewGuid(), deleting, operation))).Rejection);
        // Until it erases again, the deletion holds no quit: quitting
        // interrupts nothing, and the next launch resumes it.
        Assert.Contains(relaunched.Send(new PrepareToQuit(Guid.NewGuid())), change => change is CloseReady { Allowed: true });
        relaunched.Send(new DeleteProfileData(Guid.NewGuid(), profile, Ephemeral: false));
        relaunched.Report(engines.WebKit,
            new DataErased(Assert.IsType<EraseProfileData>(Assert.Single(engines.WebKitBinding.Commands)).ErasureId, Erased: true));
        relaunched.Report(engines.Chromium,
            new DataErased(Assert.IsType<EraseProfileData>(Assert.Single(engines.ChromiumBinding.Commands)).ErasureId, Erased: true));
        Assert.True(Assert.Single(relaunched.Drain().OfType<DataDeleted>()).Deleted);
        // Once the profile is erased, a quit no longer interrupts anything.
        Assert.Contains(relaunched.Send(new PrepareToQuit(Guid.NewGuid())), change => change is CloseReady { Allowed: true });
        relaunched.Send(new FinishDeletingSpace(again, Guid.NewGuid(), deleting, operation));
        Assert.DoesNotContain(relaunched.Workspace(again).Current.Spaces, space => space.Id == deleting);
    }
}
