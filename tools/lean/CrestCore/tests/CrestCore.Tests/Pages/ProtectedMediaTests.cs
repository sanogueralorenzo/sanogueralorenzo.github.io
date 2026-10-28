using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The protected media fallback: a page whose engine cannot play the key
/// system it asked for moves, once, to an engine that plays protected media
/// through the platform, without storing a rule for future pages.
public sealed partial class BrowserContractsTests {
    /// A live page of the fixture tab on a default Chromium binding, with a
    /// WebKit binding beside it that plays protected media when `webKitPlays`.
    private static (CrestApp App, Engine Chromium, RecordingEngine ChromiumBinding, Engine WebKit, RecordingEngine WebKitBinding,
        Guid Page, Guid Workspace, Guid Window, Guid Space, Guid Tab) ChromiumPage(bool webKitPlays = true) {
        var fixture = SavedSession();
        var app = new CrestApp();
        var (chromiumBinding, webKitBinding) = (new RecordingEngine(), new RecordingEngine());
        var chromium = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true),
            chromiumBinding.Run);
        var webKit = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit,
            webKitPlays ? [.. EngineCapability.Required, EngineCapability.ProtectedMedia] : EngineCapability.Required, IsDefault: false),
            webKitBinding.Run);
        var workspace = TestWorkspaces.Open(app, fixture.Document["session"]!);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, fixture.Space, fixture.Tab, window));
        app.Report(chromium, new PageCreated(page));
        app.Report(chromium, new NavigationCommitted(page, TabUrl(app, workspace, fixture.Space, fixture.Tab), SameDocument: false));
        app.Drain();
        return (app, chromium, chromiumBinding, webKit, webKitBinding, page, workspace, window, fixture.Space, fixture.Tab);
    }

    private static string TabUrl(CrestApp app, Guid workspace, Guid space, Guid tab) =>
        app.Workspace(workspace).Current.Spaces.Single(held => held.Id == space).Tabs.Single(held => held.Id == tab).Url!;

    [Fact]
    public void APageMovesOnceForProtectedMediaWithoutChangingTheEngineForFuturePages() {
        var (app, chromium, chromiumBinding, webKit, webKitBinding, page, workspace, window, space, tab) = ChromiumPage();
        using var disposal = app;
        var url = TabUrl(app, workspace, space, tab);
        var site = new WebAddress(url).Origin!;

        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.Widevine));
        Assert.Empty(app.Drain());
        Assert.Equal(new CheckBeforeUnload(page), chromiumBinding.Commands[^1]);
        app.Report(chromium, new BeforeUnloadAnswered(page, Proceeds: true));
        var moved = app.Drain();
        Assert.Equal(new PageRehosted(page, space, site, EngineKind.Chromium, EngineKind.WebKit, RehostReason.ProtectedMedia),
            Assert.Single(moved.OfType<PageRehosted>()));
        Assert.Equal(EngineKind.WebKit, Assert.Single(moved.OfType<PageChanged>()).Page.Engine);
        Assert.Equal(new ClosePage(page, KeepsState: true), chromiumBinding.Commands[^1]);
        app.Report(webKit, new PageCreated(page));
        Assert.Equal(new LoadPage(page, url), webKitBinding.Commands[^1]);

        // A repeat from the old engine changes nothing; the next page uses the global default.
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.Widevine));
        Assert.Empty(app.Drain().OfType<PageRehosted>());
        app.Send(new ReleasePage(page, KeepsState: false));
        var next = Guid.NewGuid();
        app.Send(new OpenPage(next, workspace, space, tab, window));
        Assert.Equal(next, Assert.IsType<CreatePage>(chromiumBinding.Commands[^1]).PageId);
    }

    [Fact]
    public void AMovedBackPageNeverBounces() {
        var (app, chromium, chromiumBinding, webKit, _, page, workspace, window, space, tab) = ChromiumPage();
        using var disposal = app;
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.PlayReady));
        app.Report(chromium, new BeforeUnloadAnswered(page, Proceeds: true));
        app.Report(webKit, new PageCreated(page));

        // Moving back affects this page only.
        app.Drain();
        app.Send(new RehostPage(page, EngineKind.Chromium));
        app.Report(webKit, new BeforeUnloadAnswered(page, Proceeds: true));
        var back = app.Drain();
        Assert.Equal(RehostReason.PersonAsked, Assert.Single(back.OfType<PageRehosted>()).Reason);
        app.Report(chromium, new PageCreated(page));
        app.Drain();

        // The page asks again on Chromium, and stays.
        int commands = chromiumBinding.Commands.Count;
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.PlayReady));
        Assert.Empty(app.Drain().OfType<PageRehosted>());
        Assert.Equal(commands, chromiumBinding.Commands.Count);

    }

    [Fact]
    public void ACanceledAutomaticMovePreservesThePageWithoutRepeatedPrompts() {
        var (app, chromium, binding, _, fallback, page, workspace, window, space, tab) = ChromiumPage();
        using var disposal = app;
        int commands = binding.Commands.Count;
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.Widevine));
        Assert.Empty(app.Drain());
        Assert.Equal(new CheckBeforeUnload(page), binding.Commands[^1]);
        app.Report(chromium, new BeforeUnloadAnswered(page, Proceeds: false));
        Assert.Empty(app.Drain());
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.PlayReady));
        Assert.Empty(app.Drain());
        Assert.Equal(commands + 1, binding.Commands.Count);
        Assert.Empty(fallback.Commands);
        Assert.Equal(new CheckBeforeUnload(page), binding.Commands[^1]);

        // A canceled move leaves future tabs on the global default.
        var next = Guid.NewGuid();
        app.Send(new OpenPage(next, workspace, space, null, window));
        Assert.Equal(next, Assert.IsType<CreatePage>(binding.Commands[^1]).PageId);
        app.Send(new Navigate(next, TabUrl(app, workspace, space, tab)));
        Assert.Empty(fallback.Commands);
    }

    [Fact]
    public void AnAutomaticMoveCannotReplaceADocumentThatChangedDuringBeforeUnload() {
        var (app, chromium, binding, _, fallback, page, _, _, _, _) = ChromiumPage();
        using var disposal = app;
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.Widevine));
        Assert.Empty(app.Drain());
        app.Report(chromium, new NavigationCommitted(page, "https://example.org/another", SameDocument: false));
        app.Drain();
        int commands = binding.Commands.Count;

        app.Report(chromium, new BeforeUnloadAnswered(page, Proceeds: true));
        Assert.Empty(app.Drain());
        Assert.Equal(commands, binding.Commands.Count);
        Assert.Empty(fallback.Commands);
    }

    [Fact]
    public void NothingMovesWithoutAnEngineThatPlaysProtectedMedia() {
        var (app, chromium, chromiumBinding, _, webKitBinding, page, _, _, _, _) = ChromiumPage(webKitPlays: false);
        using var disposal = app;
        int commands = chromiumBinding.Commands.Count;

        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.Widevine));

        Assert.Empty(app.Drain());
        Assert.Equal(commands, chromiumBinding.Commands.Count);
        Assert.Empty(webKitBinding.Commands);
    }
}
