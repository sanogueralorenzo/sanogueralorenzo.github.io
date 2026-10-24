using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Memory pressure unloads the pages off screen longest, never one a window
/// shows, one running media, one showing no document yet or one whose tab
/// keeps its page loaded, cleanup never archives a tab whose page runs media,
/// and a tab whose page was unloaded restores it only while the tab is still
/// open.
public sealed partial class BrowserContractsTests {
    /// A desktop host whose clock the test moves, on an engine that can bring
    /// pages back, with one window open over a saved session whose one tab
    /// keeps its page loaded.
    private static (CrestApp App, Engine Engine, RecordingEngine Binding, TestClock Clock, Guid Workspace, Guid Window, Guid Space,
        Guid KeptLoaded) ResidentHost() {
        var clock = new TestClock(new DateTimeOffset(2026, 9, 26, 12, 0, 0, TimeSpan.Zero));
        var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Desktop), clock, new TestIds());
        var binding = new RecordingEngine();
        var engine = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium,
            [.. EngineCapability.Required, EngineCapability.PageResidency], IsDefault: true), binding.Run);
        var fixture = SavedSession();
        var workspace = TestWorkspaces.Open(app, fixture.Document["session"]!);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        return (app, engine, binding, clock, workspace, window, fixture.Space, fixture.Tab);
    }

    /// A new open tab at `address` with a live page showing it, unless
    /// `blank`, which the window shows, a minute after the last one.
    private static (Guid Tab, Guid Page) ShowNewTab(CrestApp app, Engine engine, TestClock clock, Guid workspace, Guid window,
        Guid space, string address, bool blank = false) {
        clock.Now += TimeSpan.FromMinutes(1);
        var (tab, page) = (Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenTab(workspace, window, space, tab, new TabContent(address, null, "Page"), TabPlacement.Current, null,
            Shows: true));
        app.Send(new OpenPage(page, workspace, space, tab, window));
        app.Report(engine, new PageCreated(page));
        if (!blank) app.Report(engine, new PageStateChanged(page, Showing(address)));
        app.Send(new ShowTab(window, space, tab));
        return (tab, page);
    }

    private static IEnumerable<Guid> Unloaded(IReadOnlyList<Change> changes) => changes.OfType<PageUnloaded>().Select(unloaded => unloaded.PageId);

    [Fact]
    public void PressureUnloadsThePagesOffScreenLongestAndNeverOneShownPlayingOrKeptLoaded() {
        var (app, engine, binding, clock, workspace, window, space, keptTab) = ResidentHost();
        using var disposal = app;
        var kept = Guid.NewGuid();
        app.Send(new OpenPage(kept, workspace, space, keptTab, window));
        app.Report(engine, new PageCreated(kept));
        var (_, blank) = ShowNewTab(app, engine, clock, workspace, window, space, "https://blank.example/", blank: true);
        var (_, first) = ShowNewTab(app, engine, clock, workspace, window, space, "https://first.example/");
        var (_, playing) = ShowNewTab(app, engine, clock, workspace, window, space, "https://playing.example/");
        var (_, floating) = ShowNewTab(app, engine, clock, workspace, window, space, "https://floating.example/");
        var (_, sharing) = ShowNewTab(app, engine, clock, workspace, window, space, "https://sharing.example/");
        var (_, second) = ShowNewTab(app, engine, clock, workspace, window, space, "https://second.example/");
        var (left, leftPage) = ShowNewTab(app, engine, clock, workspace, window, space, "https://left.example/");
        var (right, rightPage) = ShowNewTab(app, engine, clock, workspace, window, space, "https://right.example/");
        app.Send(new JoinSplit(workspace, window, space, right, left, null));
        app.Report(engine, new PageStateChanged(playing, Showing("https://playing.example/") with { Media = PageMediaActivity.Playing }));
        // A video paused in its Picture in Picture window, and a screen being
        // shared, run media as much as a video playing does.
        app.Report(engine, new PageStateChanged(floating,
            Showing("https://floating.example/") with { Media = PageMediaActivity.PictureInPicture }));
        app.Report(engine, new PageStateChanged(sharing, Showing("https://sharing.example/") with { Media = PageMediaActivity.Capturing }));
        app.Drain();

        // A warning takes back one page on the desktop: the one off screen
        // longest that shows a document and whose tab does not keep it loaded.
        Assert.Equal([first], Unloaded(app.Send(new ReportMemoryPressure(MemoryPressureLevel.Warning))));
        Assert.Equal(new ClosePage(first, KeepsState: true), binding.Commands[^1]);

        // Critical pressure takes half of what is left, at least one; the pages
        // running media, the page showing nothing yet and both cards of the
        // split on screen stay whatever the level.
        Assert.Equal([second], Unloaded(app.Send(new ReportMemoryPressure(MemoryPressureLevel.Critical))));
        Assert.Empty(Unloaded(app.Send(new ReportMemoryPressure(MemoryPressureLevel.Critical))));
        Assert.DoesNotContain(binding.Commands, command => command is ClosePage closing
            && (closing.PageId == kept || closing.PageId == blank || closing.PageId == playing || closing.PageId == floating
                || closing.PageId == sharing || closing.PageId == leftPage || closing.PageId == rightPage));
    }

    [Fact]
    public void CleanupKeepsATabOpenWhileItsPageRunsMedia() {
        var (app, engine, _, clock, workspace, window, space, _) = ResidentHost();
        using var disposal = app;
        var (quiet, _) = ShowNewTab(app, engine, clock, workspace, window, space, "https://quiet.example/");
        var (floating, floatingPage) = ShowNewTab(app, engine, clock, workspace, window, space, "https://floating.example/");
        ShowNewTab(app, engine, clock, workspace, window, space, "https://shown.example/");
        app.Report(engine, new PageStateChanged(floatingPage,
            Showing("https://floating.example/") with { Media = PageMediaActivity.PictureInPicture }));
        app.Drain();

        // A day after the tab was last used, cleanup archives the tab nobody
        // used, but not the one whose video still floats in Picture in Picture.
        IEnumerable<TabState> Tabs() => app.Workspace(workspace).Current.Spaces.Single(candidate => candidate.Id == space).Tabs;
        clock.Now = Tabs().Single(tab => tab.Id == quiet).LastActivatedAt + TimeSpan.FromDays(1);
        app.Send(new CleanUpCurrentTabs(workspace, space));
        var open = Tabs().Select(tab => tab.Id).ToArray();
        Assert.DoesNotContain(quiet, open);
        Assert.Contains(floating, open);
    }

    [Fact]
    public void PressureKeepsAPageAnotherWindowShows() {
        var (app, engine, _, clock, workspace, window, space, _) = ResidentHost();
        using var disposal = app;
        var (shared, _) = ShowNewTab(app, engine, clock, workspace, window, space, "https://shared.example/");
        var (_, hidden) = ShowNewTab(app, engine, clock, workspace, window, space, "https://hidden.example/");
        ShowNewTab(app, engine, clock, workspace, window, space, "https://shown.example/");
        var second = Guid.NewGuid();
        app.Send(new OpenWindow(second, workspace, Saved: false, null, null, [], RestoresTabs: true));
        app.Send(new ShowTab(second, space, shared));

        // The page off its own window's screen longest stays, because another
        // window shows its tab; the next one goes.
        Assert.Equal([hidden], Unloaded(app.Send(new ReportMemoryPressure(MemoryPressureLevel.Warning))));
    }

    [Fact]
    public void AnUnloadedTabRestoresItsPageOnceAtTheSameAddressAndAClosedTabFreesWhatItKept() {
        var (app, engine, binding, clock, workspace, window, space, _) = ResidentHost();
        using var disposal = app;
        var (tab, page) = ShowNewTab(app, engine, clock, workspace, window, space, "https://kept.example/");
        var (other, otherPage) = ShowNewTab(app, engine, clock, workspace, window, space, "https://other.example/");
        ShowNewTab(app, engine, clock, workspace, window, space, "https://shown.example/");
        var kept = new PageRestoreState("https://kept.example/", [1, 2, 3]);

        Assert.Equal([page], Unloaded(app.Send(new ReportMemoryPressure(MemoryPressureLevel.Critical))));
        Assert.Equal([otherPage], Unloaded(app.Send(new ReportMemoryPressure(MemoryPressureLevel.Critical))));
        app.Report(engine, new PageClosed(page, kept));
        app.Report(engine, new PageClosed(otherPage, kept with { Url = "https://other.example/" }));

        // The tab's next page restores what it kept, heading there at once; the one after loads anew.
        var restored = Guid.NewGuid();
        var opened = Assert.Single(app.Send(new OpenPage(restored, workspace, space, tab, window)).OfType<PageOpened>());
        Assert.Equal("https://kept.example/", opened.Page.Live.PendingUrl);
        Assert.Equal(new CreatePage(restored, ProfileOf(app, workspace, space), IsPrivate: false, window, kept), binding.Commands[^1]);
        app.Send(new ReleasePage(restored, KeepsState: false));
        app.Send(new OpenPage(Guid.NewGuid(), workspace, space, tab, window));
        Assert.Null(Assert.IsType<CreatePage>(binding.Commands[^1]).RestoreState);

        // A tab that closes frees what it kept, even when it is reopened later.
        app.Send(new CloseTab(workspace, window, space, other));
        app.Send(new RestoreArchivedTab(workspace, window, space, other));
        app.Send(new OpenPage(Guid.NewGuid(), workspace, space, other, window));
        Assert.Null(Assert.IsType<CreatePage>(binding.Commands[^1]).RestoreState);
    }

    public static TheoryData<MemoryPressureLevel, DevicePlatform, int, int> ReleaseBudgets => new() {
        { MemoryPressureLevel.Warning, DevicePlatform.Desktop, 8, 1 },
        { MemoryPressureLevel.Critical, DevicePlatform.Desktop, 8, 4 },
        { MemoryPressureLevel.Critical, DevicePlatform.Desktop, 7, 4 },
        { MemoryPressureLevel.Critical, DevicePlatform.Desktop, 1, 1 },
        { MemoryPressureLevel.Warning, DevicePlatform.Mobile, 8, 0 },
        { MemoryPressureLevel.Critical, DevicePlatform.Mobile, 8, 1 },
    };

    /// The Mac gives back one page under warning pressure and half of them, at
    /// least one, under critical pressure; iPhone and iPad hold on under warning
    /// pressure and give back one page under critical pressure.
    [Theory]
    [MemberData(nameof(ReleaseBudgets))]
    public void MemoryPressureBudgetsDifferByPlatformAndSeverity(MemoryPressureLevel level, DevicePlatform platform, int eligible,
        int limit) =>
        Assert.Equal(limit, platform.ReleaseLimit(level, eligible));
}
