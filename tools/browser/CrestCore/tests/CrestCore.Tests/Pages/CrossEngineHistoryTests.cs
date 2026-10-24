using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A page's history across engines: a page that moves to another engine keeps
/// what it could go back to, going back returns to the engine that held that
/// entry with the history it kept, and going forward returns to the engine
/// the page moved to.
public sealed partial class BrowserContractsTests {
    private static PageRestoreState Kept(string url) => new(url, [1, 2, 3]);

    /// The fixture page on Chromium after it showed `earlier` then the tab's
    /// page, moved to WebKit for protected media, and WebKit showed the tab's
    /// page. Answers the entries each engine reported.
    private static (PageHistoryEntry Earlier, PageHistoryEntry Moved, PageHistoryEntry Shown) MovedForProtectedMedia(
        CrestApp app, Engine chromium, Engine webKit, Guid page, string url, PageRestoreState? kept) {
        var earlier = Entry("https://earlier.example/");
        var moved = Entry(url);
        app.Report(chromium, new PageHistoryReported(page, [earlier, moved], Current: 1));
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.Widevine));
        app.Report(chromium, new BeforeUnloadAnswered(page, Proceeds: true));
        app.Report(chromium, new PageClosed(page, kept));
        app.Report(webKit, new PageCreated(page));
        // Until the new engine reports its history, the page offers no entry to go to.
        var moving = app.Query(new PageHistoryEntries(page));
        Assert.Equal((0, 0), (moving.Back.Count, moving.Forward.Count));
        var shown = Entry(url);
        app.Report(webKit, new PageHistoryReported(page, [shown], Current: 0));
        app.Drain();
        return (earlier, moved, shown);
    }

    [Fact]
    public void BackAfterAMoveReturnsToTheEngineThatHeldTheEntryAndForwardReturnsAgain() {
        var (app, chromium, chromiumBinding, webKit, webKitBinding, page, workspace, _, space, tab) = ChromiumPage();
        using var disposal = app;
        var url = TabUrl(app, workspace, space, tab);
        var chromiumKept = Kept(url);
        var (earlier, moved, shown) = MovedForProtectedMedia(app, chromium, webKit, page, url, chromiumKept);

        // The page can go back to what led up to the document that moved, which it shows once, on WebKit.
        Assert.True(app.Pages.Hosted(page)!.Live.CanGoBack);
        Assert.Equal([earlier], app.Query(new PageHistoryEntries(page)).Back);

        // Going back asks WebKit's page first, then Chromium restores what it kept and goes to the entry.
        app.Send(new StepHistory(page, -1));
        Assert.Equal(new CheckBeforeUnload(page), webKitBinding.Commands[^1]);
        app.Report(webKit, new BeforeUnloadAnswered(page, Proceeds: true));
        Assert.Equal(new ClosePage(page, KeepsState: true), webKitBinding.Commands[^1]);
        var profile = Assert.IsType<CreatePage>(chromiumBinding.Commands[^1]).ProfileId;
        Assert.Equal(new CreatePage(page, profile, IsPrivate: false, app.Pages.Hosted(page)!.WindowId, chromiumKept),
            chromiumBinding.Commands[^1]);
        var webKitKept = Kept(url);
        app.Report(webKit, new PageClosed(page, webKitKept));
        app.Report(chromium, new PageCreated(page));
        Assert.IsType<CreatePage>(chromiumBinding.Commands[^1]);
        // A new Chromium page first reports that it holds no history, which changes nothing.
        app.Report(chromium, new PageHistoryReported(page, [], Current: -1));
        app.Report(chromium, new PageHistoryReported(page, [earlier, moved], Current: 1));
        Assert.Equal(new GoToHistoryEntry(page, earlier.Id), chromiumBinding.Commands[^1]);
        app.Report(chromium, new PageHistoryReported(page, [earlier, moved], Current: 0));
        app.Drain();

        // Chromium's own copy of the moved document is not offered; forward returns to WebKit's.
        var history = app.Query(new PageHistoryEntries(page));
        Assert.Empty(history.Back);
        Assert.Equal([shown], history.Forward);

        // Going forward returns to WebKit, which restores the history it kept and already shows the entry.
        app.Send(new StepHistory(page, 1));
        app.Report(chromium, new BeforeUnloadAnswered(page, Proceeds: true));
        Assert.Equal(new CreatePage(page, profile, IsPrivate: false, app.Pages.Hosted(page)!.WindowId, webKitKept),
            webKitBinding.Commands[^1]);
        app.Report(chromium, new PageClosed(page, chromiumKept));
        app.Report(webKit, new PageCreated(page));
        int issued = webKitBinding.Commands.Count;
        // WebKit gives restored entries new identities, which the core takes on in order.
        var restored = shown with { Id = Guid.NewGuid() };
        app.Report(webKit, new PageHistoryReported(page, [restored], Current: 0));
        Assert.Equal(issued, webKitBinding.Commands.Count);
        Assert.Equal([earlier], app.Query(new PageHistoryEntries(page)).Back);

        // The protected-media fallback never moves the page back on its own.
        app.Send(new StepHistory(page, -1));
        app.Report(webKit, new BeforeUnloadAnswered(page, Proceeds: true));
        app.Report(chromium, new PageCreated(page));
        app.Report(chromium, new ProtectedMediaUnavailable(page, KeySystem.Widevine));
        Assert.IsNotType<CheckBeforeUnload>(chromiumBinding.Commands[^1]);
    }

    [Fact]
    public void ANewNavigationAfterGoingBackLeavesNoForwardHistoryOnAnyEngine() {
        var (app, chromium, chromiumBinding, webKit, webKitBinding, page, workspace, _, space, tab) = ChromiumPage();
        using var disposal = app;
        var url = TabUrl(app, workspace, space, tab);
        var (earlier, moved, _) = MovedForProtectedMedia(app, chromium, webKit, page, url, Kept(url));
        app.Send(new StepHistory(page, -1));
        app.Report(webKit, new BeforeUnloadAnswered(page, Proceeds: true));
        app.Report(webKit, new PageClosed(page, Kept(url)));
        app.Report(chromium, new PageCreated(page));
        app.Report(chromium, new PageHistoryReported(page, [earlier, moved], Current: 0));
        Assert.True(app.Pages.Hosted(page)!.Live.CanGoForward);

        // A link from the earlier page replaces Chromium's forward entries, and WebKit's go with them.
        var next = Entry("https://next.example/");
        app.Report(chromium, new PageHistoryReported(page, [earlier, next], Current: 1));
        var history = app.Query(new PageHistoryEntries(page));
        Assert.Equal([earlier], history.Back);
        Assert.Empty(history.Forward);
        Assert.False(app.Pages.Hosted(page)!.Live.CanGoForward);
    }

    [Fact]
    public void AnEntryWhoseEngineKeptNoHistoryLoadsAfreshAsItself() {
        var (app, chromium, chromiumBinding, webKit, webKitBinding, page, workspace, _, space, tab) = ChromiumPage();
        using var disposal = app;
        var url = TabUrl(app, workspace, space, tab);
        var (earlier, _, _) = MovedForProtectedMedia(app, chromium, webKit, page, url, kept: null);

        app.Send(new ShowHistoryEntry(page, earlier.Id));
        app.Report(webKit, new BeforeUnloadAnswered(page, Proceeds: true));
        Assert.Null(Assert.IsType<CreatePage>(chromiumBinding.Commands[^1]).RestoreState);
        app.Report(chromium, new PageCreated(page));
        Assert.Equal(new LoadPage(page, earlier.Url, earlier.Id), chromiumBinding.Commands[^1]);

        // A canceled before-unload answer leaves the page where it is.
        app.Report(chromium, new PageHistoryReported(page, [earlier], Current: 0));
        app.Send(new StepHistory(page, 1));
        app.Report(chromium, new BeforeUnloadAnswered(page, Proceeds: false));
        Assert.Equal(EngineKind.Chromium, app.Pages.Hosted(page)!.Engine.Kind);
    }

    [Fact]
    public void AnOverflowingHistoryPointsARunThatLostItsShownEntryAtTheFirstEntryItKeeps() {
        var history = new PageHistory();
        PageHistoryEntry[] chromium = [.. Enumerable.Range(0, 4).Select(index => Entry($"https://chromium.example/{index}"))];
        // The page goes back to the oldest entry, then forward by loading the newest afresh, which leaves the
        // older run holding three entries and last showing the first.
        history.Report(EngineKind.Chromium, chromium, current: 0);
        history.Return(chromium[3].Id);
        history.Report(EngineKind.Chromium, chromium, current: 3);
        history.Leave(EngineKind.WebKit, "https://webkit.example/");
        history.Keep(EngineKind.Chromium, Kept("https://chromium.example/3"));

        // One entry too many drops that first entry.
        PageHistoryEntry[] webKit = [.. Enumerable.Range(0, PageHistory.Capacity - 4 + 1).Select(index => Entry($"https://webkit.example/{index}"))];
        history.Report(EngineKind.WebKit, webKit, current: webKit.Length - 1);
        Assert.Equal(PageHistory.Capacity, history.Entries.Count);
        Assert.DoesNotContain(chromium[0], history.Entries);

        // Returning to the run brings back the first entry that remains.
        history.Return(chromium[1].Id);
        Assert.Equal(chromium[1], history.Shown);
    }
}
