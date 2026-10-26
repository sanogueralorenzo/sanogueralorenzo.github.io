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
}
