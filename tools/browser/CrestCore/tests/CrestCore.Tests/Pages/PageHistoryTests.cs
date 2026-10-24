using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A page's back and forward history: the core reads the list its engine
/// reported for whether the page can go back or forward and for its menus,
/// and every step or menu choice asks the engine for an entry it reported.
public sealed partial class BrowserContractsTests {
    private static PageHistoryEntry Entry(string url) => new(Guid.NewGuid(), url, Title: url);

    [Fact]
    public void AReportedHistoryDecidesWhetherAPageCanGoBackOrForwardAndWhatItsMenusOffer() {
        var (app, engine, _, page, _, _, _, _) = LivePage();
        using var disposal = app;
        PageHistoryEntry[] entries = [Entry("https://a.example/"), Entry("https://b.example/"), Entry("https://c.example/")];

        app.Report(engine, new PageHistoryReported(page, entries, Current: 1));
        var live = Live(app.Drain());
        Assert.Equal((true, true), (live.CanGoBack, live.CanGoForward));
        var menus = app.Query(new PageHistoryEntries(page));
        Assert.Equal([entries[0]], menus.Back);
        Assert.Equal([entries[2]], menus.Forward);

        // The same history again changes nothing, and one no engine could hold is ignored.
        app.Report(engine, new PageHistoryReported(page, entries, Current: 1));
        app.Report(engine, new PageHistoryReported(page, entries, Current: 3));
        app.Report(engine, new PageHistoryReported(page, [entries[0], entries[0]], Current: 0));
        Assert.Empty(app.Drain());

        // The newest entry reaches back to all the others, nearest first.
        app.Report(engine, new PageHistoryReported(page, entries, Current: 2));
        var newest = Live(app.Drain());
        Assert.Equal((true, false), (newest.CanGoBack, newest.CanGoForward));
        Assert.Equal([entries[1], entries[0]], app.Query(new PageHistoryEntries(page)).Back);
        var unknown = app.Query(new PageHistoryEntries(Guid.NewGuid()));
        Assert.Equal((0, 0), (unknown.Back.Count, unknown.Forward.Count));
    }

    [Fact]
    public void StepsAndMenuChoicesAskTheEngineForAnEntryItReported() {
        var (app, engine, binding, page, _, _, _, _) = LivePage();
        using var disposal = app;
        PageHistoryEntry[] entries = [Entry("https://a.example/"), Entry("https://b.example/"), Entry("https://c.example/")];
        app.Report(engine, new PageHistoryReported(page, entries, Current: 1));
        app.Drain();

        app.Send(new StepHistory(page, -1));
        Assert.Equal(new GoToHistoryEntry(page, entries[0].Id), binding.Commands[^1]);
        app.Send(new StepHistory(page, 1));
        Assert.Equal(new GoToHistoryEntry(page, entries[2].Id), binding.Commands[^1]);
        app.Send(new ShowHistoryEntry(page, entries[0].Id));
        Assert.Equal(new GoToHistoryEntry(page, entries[0].Id), binding.Commands[^1]);

        // A step past either end, the entry the page shows, or one it never reported goes nowhere.
        int issued = binding.Commands.Count;
        app.Send(new StepHistory(page, -2));
        app.Send(new StepHistory(page, 2));
        app.Send(new ShowHistoryEntry(page, entries[1].Id));
        app.Send(new ShowHistoryEntry(page, Guid.NewGuid()));
        Assert.Equal(issued, binding.Commands.Count);
        Assert.Equal(new UnknownPage(Guid.Empty), Refusal(app, new StepHistory(Guid.Empty, -1)));
    }

    [Fact]
    public void GoingBackFromAFailureLeavesItAndGoesPastOnlyOneThatReplacedTheDocument() {
        var (app, engine, binding, page, _, _, _, _) = LivePage();
        using var disposal = app;
        PageHistoryEntry[] entries = [Entry("https://a.example/"), Entry("https://b.example/")];
        app.Report(engine, new PageStateChanged(page, Showing("https://b.example/")));
        app.Report(engine, new PageHistoryReported(page, entries, Current: 1));
        app.Drain();
        var failure = new PageFailure(NavigationError.CannotFindServer, "https://missing.example/", ReplacedDocument: false,
            "NSURLErrorDomain", -1003);

        // A failure over the document the page shows returns to that document.
        app.Report(engine, new NavigationFailed(page, failure));
        app.Drain();
        int issued = binding.Commands.Count;
        Assert.Null(Live(app.Send(new StepHistory(page, -1))).Failure);
        Assert.Equal(issued, binding.Commands.Count);

        // One that replaced it goes back past it.
        app.Report(engine, new NavigationFailed(page, failure with { ReplacedDocument = true }));
        app.Drain();
        Assert.Null(Live(app.Send(new StepHistory(page, -1))).Failure);
        Assert.Equal(new GoToHistoryEntry(page, entries[0].Id), binding.Commands[^1]);
    }
}
