using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A video a page floats in Picture in Picture goes back into its page once a
/// window shows the page again, however the person came back to it, or once
/// its Space locks, and the Picture in Picture window's return control shows
/// the person the page's tab in its window and Space, bringing that window
/// forward.
public sealed partial class BrowserContractsTests {
    private const PageMediaActivity Floating = PageMediaActivity.Playing | PageMediaActivity.PictureInPicture;

    private static int Exits(RecordingEngine binding, Guid page) =>
        binding.Commands.Count(command => command == new ExitPictureInPicture(page));

    [Fact]
    public void APageShownAgainEndsItsPictureInPictureAndOneStillOnScreenKeepsIt() {
        var (app, engine, binding, clock, workspace, window, space, _) = ResidentHost();
        using var disposal = app;
        var (videoTab, video) = ShowNewTab(app, engine, clock, workspace, window, space, "https://video.example/");

        // The person floats the video while its tab is on screen, and it stays.
        app.Report(engine, new PageStateChanged(video, Showing("https://video.example/") with { Media = Floating }));
        app.Send(new ShowTab(window, space, videoTab));
        Assert.Equal(0, Exits(binding, video));

        // Leaving the tab keeps the video floating; coming back ends it once,
        // here by the most recent tab's shortcut.
        var (otherTab, other) = ShowNewTab(app, engine, clock, workspace, window, space, "https://other.example/");
        Assert.Equal(0, Exits(binding, video));
        app.Send(new ShowMostRecentTab(window));
        Assert.Equal(1, Exits(binding, video));

        // A video that floated as its tab left comes back when the tab is
        // chosen again, and a page with none floating is asked for nothing.
        app.Report(engine, new PageStateChanged(video, Showing("https://video.example/")));
        app.Send(new ShowTab(window, space, otherTab));
        app.Report(engine, new PageStateChanged(video, Showing("https://video.example/") with { Media = Floating }));
        app.Send(new ShowTab(window, space, videoTab));
        Assert.Equal(2, Exits(binding, video));
        Assert.Equal(0, Exits(binding, other));
    }

    [Fact]
    public void LockingASpaceEndsThePictureInPictureOfItsPagesAndNoOtherSpaces() {
        var session = TwoSpaceSession();
        session["spaces"]![0]!["accessPolicy"] = "deviceOwnerAuthentication";
        var (guarded, open) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var clock = new TestClock(new DateTimeOffset(2026, 9, 27, 12, 0, 0, TimeSpan.Zero));
        var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Desktop), clock, new TestIds());
        using var disposal = app;
        var binding = new RecordingEngine();
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true),
            binding.Run);
        var workspace = TestWorkspaces.Open(app, session);
        TestGrants.Unlock(app.Send, workspace, guarded);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var (_, video) = ShowNewTab(app, engine, clock, workspace, window, guarded, "https://video.example/");
        var peek = Guid.NewGuid();
        app.Send(new OpenPage(peek, workspace, guarded, null, window, TransientPresentation.Peek));
        app.Report(engine, new PageCreated(peek));
        var (_, other) = ShowNewTab(app, engine, clock, workspace, window, open, "https://other.example/");

        // The guarded Space's tab and Peek float videos, as does a tab of the
        // open Space the window shows; the lock ends only the guarded Space's.
        foreach (var page in new[] { video, peek, other })
            app.Report(engine, new PageStateChanged(page, Showing("https://video.example/") with { Media = Floating }));
        Assert.Equal(0, Exits(binding, video) + Exits(binding, peek) + Exits(binding, other));
        app.Send(new LockAllSpaces(SceneWentInactive: false));
        Assert.Equal((1, 1, 0), (Exits(binding, video), Exits(binding, peek), Exits(binding, other)));

        // A video that floats again while its Space is locked is ended at once.
        app.Report(engine, new PageStateChanged(video, Showing("https://video.example/")));
        app.Report(engine, new PageStateChanged(video, Showing("https://video.example/") with { Media = Floating }));
        Assert.Equal(2, Exits(binding, video));
    }

    [Fact]
    public void ReturningFromPictureInPictureShowsThePagesTabInItsWindowAndSpaceAndBringsThatWindowForward() {
        var session = TwoSpaceSession();
        var (space, otherSpace) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var clock = new TestClock(new DateTimeOffset(2026, 9, 27, 12, 0, 0, TimeSpan.Zero));
        var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Desktop), clock, new TestIds());
        using var disposal = app;
        var binding = new RecordingEngine();
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true),
            binding.Run);
        var workspace = TestWorkspaces.Open(app, session);
        var (window, second) = (Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var (videoTab, video) = ShowNewTab(app, engine, clock, workspace, window, space, "https://video.example/");
        app.Report(engine, new PageStateChanged(video, Showing("https://video.example/") with { Media = Floating }));
        app.Send(new ShowSpace(window, otherSpace));
        app.Send(new OpenWindow(second, workspace, Saved: false, null, otherSpace, [], RestoresTabs: true));
        app.Drain();

        // The window that hosts the page switches back to its Space and tab,
        // and comes forward; the engine already returned the video itself.
        app.Report(engine, new PictureInPictureReturned(video));
        var returned = app.Drain();
        Assert.Contains(new WindowBroughtForward(window), returned);
        var shown = returned.OfType<WindowChanged>().Last(changed => changed.Window.Id == window).Window;
        Assert.Equal(space, shown.ShownSpaceId);
        Assert.Contains(new ShownTab(space, videoTab), shown.ShownTabs);
        app.Send(new ShowTab(window, space, videoTab));
        Assert.Equal(0, Exits(binding, video));

        // Once that window closes, another over the workspace shows the tab;
        // with none open, nothing opens one.
        app.Send(new CloseWindow(window));
        app.Report(engine, new PictureInPictureReturned(video));
        Assert.Contains(new WindowBroughtForward(second), app.Drain());
        app.Send(new CloseWindow(second));
        app.Drain();
        app.Report(engine, new PictureInPictureReturned(video));
        Assert.DoesNotContain(app.Drain(), change => change is WindowBroughtForward or WindowChanged);
    }
}
