using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

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

        // Sites' data goes the same way, by their hosts, and only a private
        // profile's memory is touched for one that is ephemeral.
        var clearing = Guid.NewGuid();
        app.Send(new DeleteSiteData(clearing, profile, Ephemeral: true, ["Example.COM", " example.com", "www.other.org"],
            [BrowsingDataCategory.Cache, BrowsingDataCategory.History, BrowsingDataCategory.SiteData]));
        var site = Assert.IsType<EraseSiteData>(webKitBinding.Commands[^1]);
        Assert.Equal((profile, true), (site.ProfileId, site.Ephemeral));
        Assert.Equal(["example.com", "www.other.org"], site.Hosts);
        // A site's history is not its data: only the categories a site's
        // share can be cleared by reach the engines.
        Assert.Equal([BrowsingDataCategory.SiteData, BrowsingDataCategory.Cache], site.Categories);
        app.Report(webKit, new DataErased(site.ErasureId, Erased: true));
        app.Report(chromium, new DataErased(Assert.IsType<EraseSiteData>(chromiumBinding.Commands[^1]).ErasureId, Erased: true));
        Assert.Equal([new DataDeleted(clearing, Deleted: true)], app.Drain().OfType<DataDeleted>());
        foreach (IReadOnlyList<string> hosts in new[] { Array.Empty<string>(), ["example.com", "  "] })
            Assert.IsType<InvalidSiteHost>(Assert.Throws<Rejected>(() =>
                app.Send(new DeleteSiteData(Guid.NewGuid(), profile, Ephemeral: false, hosts, [BrowsingDataCategory.Cache]))).Rejection);
        Assert.IsType<NoBrowsingDataCategory>(Assert.Throws<Rejected>(() =>
            app.Send(new DeleteSiteData(Guid.NewGuid(), profile, Ephemeral: false, ["example.com"], [BrowsingDataCategory.History]))).Rejection);
        // A site clear is never a profile's erasure, so a Space's deletion
        // still waits for one.
        Assert.False(app.DataDeletions.Erased(profile));
    }

    [Fact]
    public void ClearingBrowsingDataReachesBackOnlyAsFarAsItsRangeAndAsksForTheChosenCategories() {
        var clock = new TestClock(DateTimeOffset.Parse("2026-10-25T12:00:00Z"));
        using var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Desktop), clock, new SystemIdSource());
        var (webKit, webKitBinding, chromium, chromiumBinding) = IdleEngines(app);
        var profile = Guid.NewGuid();

        var request = Guid.NewGuid();
        app.Send(new DeleteBrowsingData(request, profile, Ephemeral: false, BrowsingDataRange.LastHour,
            [BrowsingDataCategory.Cache, BrowsingDataCategory.SiteData]));
        var erasing = Assert.IsType<EraseBrowsingData>(Assert.Single(webKitBinding.Commands));
        Assert.Equal(clock.Now.AddHours(-1), erasing.Since);
        Assert.Equal([BrowsingDataCategory.SiteData, BrowsingDataCategory.Cache], erasing.Categories);
        app.Report(webKit, new DataErased(erasing.ErasureId, Erased: true));
        app.Report(chromium, new DataErased(Assert.IsType<EraseBrowsingData>(Assert.Single(chromiumBinding.Commands)).ErasureId,
            Erased: false));
        Assert.Equal([new DataDeleted(request, Deleted: false)], app.Drain().OfType<DataDeleted>());

        app.Send(new DeleteBrowsingData(Guid.NewGuid(), profile, Ephemeral: false, BrowsingDataRange.AllTime,
            [BrowsingDataCategory.History]));
        Assert.Null(Assert.IsType<EraseBrowsingData>(webKitBinding.Commands[^1]).Since);
        Assert.IsType<NoBrowsingDataCategory>(Assert.Throws<Rejected>(() =>
            app.Send(new DeleteBrowsingData(Guid.NewGuid(), profile, Ephemeral: false, BrowsingDataRange.AllTime, []))).Rejection);
    }

    [Fact]
    public void TheWebsiteDataListMergesEveryEnginesSitesAndSaysWhenOneCouldNotList() {
        using var app = new CrestApp();
        var (webKit, webKitBinding, chromium, chromiumBinding) = IdleEngines(app);
        var profile = Guid.NewGuid();

        var request = Guid.NewGuid();
        app.Send(new ReadWebsiteData(request, profile, Ephemeral: false, Host: null));
        var toWebKit = Assert.IsType<ReadSiteData>(Assert.Single(webKitBinding.Commands));
        var toChromium = Assert.IsType<ReadSiteData>(Assert.Single(chromiumBinding.Commands));
        Assert.Equal((profile, false), (toWebKit.ProfileId, toWebKit.Ephemeral));
        app.Report(webKit, new SiteDataRead(toWebKit.ReadingId,
            [new StoredSite("Example.com", [WebsiteDataKind.Cache, WebsiteDataKind.Cookies]), new StoredSite("b.org", [WebsiteDataKind.Storage]),
                new StoredSite("::1", [WebsiteDataKind.Cookies])],
            Read: true));
        Assert.Empty(app.Drain().OfType<WebsiteDataRead>());
        app.Report(chromium, new SiteDataRead(toChromium.ReadingId,
            [new StoredSite("example.com", [WebsiteDataKind.Storage]), new StoredSite("[::1]", [WebsiteDataKind.Storage])], Read: false));
        var read = Assert.Single(app.Drain().OfType<WebsiteDataRead>());
        Assert.Equal(request, read.RequestId);
        Assert.False(read.Complete);
        // One engine brackets an IPv6 address and another doesn't; it is one site.
        Assert.Equal(["::1", "b.org", "example.com"], read.Sites.Select(site => site.Site));
        Assert.Equal([WebsiteDataKind.Cookies, WebsiteDataKind.Storage], read.Sites[0].Kinds);
        Assert.Equal([WebsiteDataKind.Cookies, WebsiteDataKind.Storage, WebsiteDataKind.Cache], read.Sites[2].Kinds);

        // A page's own sites: the domain it is under, never a neighbor's.
        app.Send(new ReadWebsiteData(Guid.NewGuid(), profile, Ephemeral: false, Host: "Mail.Example.com"));
        app.Report(webKit, new SiteDataRead(Assert.IsType<ReadSiteData>(webKitBinding.Commands[^1]).ReadingId,
            [new StoredSite("example.com", [WebsiteDataKind.Cookies]), new StoredSite("ample.com", [WebsiteDataKind.Cookies])], Read: true));
        app.Report(chromium, new SiteDataRead(Assert.IsType<ReadSiteData>(chromiumBinding.Commands[^1]).ReadingId, [], Read: true));
        var own = Assert.Single(app.Drain().OfType<WebsiteDataRead>());
        Assert.True(own.Complete);
        Assert.Equal("example.com", Assert.Single(own.Sites).Site);
        // A host with no name left is refused, never read as every site.
        Assert.IsType<InvalidSiteHost>(Assert.Throws<Rejected>(() =>
            app.Send(new ReadWebsiteData(Guid.NewGuid(), profile, Ephemeral: false, Host: " . "))).Rejection);
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
