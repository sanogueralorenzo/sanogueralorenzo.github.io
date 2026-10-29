using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void OnlyOneWebKitBindingRegistersAndItsCapabilitiesShapeTheUI() {
        using var app = new CrestApp();
        var incomplete = Assert.Throws<Rejected>(() => app.RegisterEngine(new EngineRegistration([]), _ => { }));
        Assert.Equal(new EngineLacksCapability(EngineCapability.Required[0]), incomplete.Rejection);
        var engine = app.RegisterEngine(new EngineRegistration(EngineCapability.Required), _ => { });
        var duplicate = Assert.Throws<Rejected>(() => app.RegisterEngine(new EngineRegistration(EngineCapability.Required), _ => { }));
        Assert.Equal(new EngineAlreadyRegistered(), duplicate.Rejection);
        var offered = Assert.Single(app.Drain().OfType<EnginesChanged>()).Roster.Offered;
        Assert.DoesNotContain(EngineCapability.Extensions, offered);
        Assert.All(EngineCapability.Required, capability => Assert.Contains(capability, offered));
        app.UnregisterEngine(engine);
        Assert.Equal(EngineCapability.All, Assert.Single(app.Drain().OfType<EnginesChanged>()).Roster.Offered);
        app.RegisterEngine(new EngineRegistration(EngineCapability.Required), _ => { });
    }

    [Fact]
    public void WebKitHistoryMenusFollowNativeTraversalAndNewNavigationReplacesForwardHistory() {
        var (app, engine, binding, page, _, _, _, _) = LivePage();
        using var disposal = app;
        var entries = HistoryEntries();
        app.Report(engine, new PageHistoryReported(page, entries, 2));
        Assert.Equal([entries[1], entries[0]], app.Query(new PageHistoryEntries(page)).Back);
        app.Send(new StepHistory(page, -1));
        Assert.Equal(new GoToHistoryEntry(page, entries[1].Id), binding.Commands[^1]);
        app.Report(engine, new PageHistoryReported(page, entries, 1));
        Assert.Equal([entries[2]], app.Query(new PageHistoryEntries(page)).Forward);
        var branch = new PageHistoryEntry(Guid.NewGuid(), "https://history.example/branch", "Branch");
        app.Report(engine, new PageHistoryReported(page, [entries[0], entries[1], branch], 2));
        Assert.Empty(app.Query(new PageHistoryEntries(page)).Forward);
        int before = binding.Commands.Count;
        app.Send(new ShowHistoryEntry(page, entries[2].Id));
        Assert.Equal(before, binding.Commands.Count);
        app.Report(engine, new PageHistoryReported(page, [branch, branch], 1));
        Assert.Equal([entries[1], entries[0]], app.Query(new PageHistoryEntries(page)).Back);
    }

    [Fact]
    public void SleepingTabRestoresNativeStateAndRenamesHistoryIdentitiesWithoutLosingItsPlace() {
        var (app, engine, binding, page, workspace, window, space, tab) = LivePage();
        using var disposal = app;
        var entries = HistoryEntries();
        CommitHistory(app, engine, page, entries);
        app.Send(new ReleasePage(page, KeepsState: true));
        var state = new PageRestoreState(entries[1].Url, [1, 2, 3]);
        app.Report(engine, new PageClosed(page, state));
        var reopened = Guid.NewGuid();
        app.Send(new OpenPage(reopened, workspace, space, tab, window));
        Assert.Equal(state, Assert.IsType<CreatePage>(binding.Commands[^1]).RestoreState);
        app.Report(engine, new PageCreated(reopened));
        var renamed = entries.Select(entry => entry with { Id = Guid.NewGuid() }).ToArray();
        app.Report(engine, new PageHistoryReported(reopened, renamed, 1));
        Assert.Equal([renamed[0]], app.Query(new PageHistoryEntries(reopened)).Back);
        Assert.Equal([renamed[2]], app.Query(new PageHistoryEntries(reopened)).Forward);
        app.Send(new StepHistory(reopened, 1));
        Assert.Equal(new GoToHistoryEntry(reopened, renamed[2].Id), binding.Commands[^1]);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ReopeningWithMissingOrUnusableNativeStateKeepsColdEntriesAndLoadsThemWhenSelected(bool hadNativeState) {
        var (app, engine, binding, page, workspace, window, space, tab) = LivePage();
        using var disposal = app;
        var entries = HistoryEntries();
        CommitHistory(app, engine, page, entries);
        app.Send(new ReleasePage(page, KeepsState: true));
        app.Report(engine, new PageClosed(page, hadNativeState ? new PageRestoreState(entries[1].Url, [1, 2, 3]) : null));
        var reopened = Guid.NewGuid();
        app.Send(new OpenPage(reopened, workspace, space, tab, window));
        Assert.Equal(hadNativeState, Assert.IsType<CreatePage>(binding.Commands[^1]).RestoreState is not null);
        app.Report(engine, new PageCreated(reopened));
        var fresh = entries[1] with { Id = Guid.NewGuid() };
        app.Report(engine, new PageHistoryReported(reopened, [fresh], 0));
        Assert.Equal([entries[0]], app.Query(new PageHistoryEntries(reopened)).Back);
        Assert.Equal([entries[2]], app.Query(new PageHistoryEntries(reopened)).Forward);
        app.Send(new ShowHistoryEntry(reopened, entries[0].Id));
        Assert.Equal(new LoadPage(reopened, entries[0].Url, entries[0].Id), binding.Commands[^1]);
        app.Report(engine, new PageHistoryReported(reopened, [fresh, entries[0]], 1));
        app.Send(new StepHistory(reopened, 1));
        Assert.Equal(new GoToHistoryEntry(reopened, fresh.Id), binding.Commands[^1]);
    }

    [Fact]
    public void SavedBrowserHistoryRestoresItsPlaceAndRejectsInvalidArchives() {
        var history = new PageHistory();
        var entries = HistoryEntries();
        history.Report(entries, 1);
        var archive = history.Archive();
        var restored = Assert.IsType<PageHistory>(PageHistory.Unarchive(archive));
        Assert.Equal(entries, restored.Entries);
        Assert.Equal(1, restored.Current);
        restored.Reopen(restores: true);
        var renamed = entries.Select(entry => entry with { Id = Guid.NewGuid() }).ToArray();
        restored.Report(renamed, 1);
        Assert.Equal([renamed[0]], restored.Back);
        Assert.Equal([renamed[2]], restored.Forward);
        Assert.Null(PageHistory.Unarchive(archive![..10]));
        var document = JsonNode.Parse(archive)!.AsObject();
        document["runs"]![0]!["entries"]![1]!["id"] = entries[0].Id.ToString();
        Assert.Null(PageHistory.Unarchive(System.Text.Encoding.UTF8.GetBytes(document.ToJsonString())));
    }

    [Fact]
    public void HistoryRejectsInvalidNativeReportsAndKeepsItsCapacityWhenColdEntriesAccumulate() {
        Assert.False(PageHistory.Holds(HistoryEntries(), -1));
        Assert.False(PageHistory.Holds(HistoryEntries(), 3));
        Assert.True(PageHistory.Holds([], -1));
        var history = new PageHistory();
        var entries = Enumerable.Range(0, PageHistory.Capacity)
            .Select(index => new PageHistoryEntry(Guid.NewGuid(), $"https://history.example/{index}", $"Page {index}")).ToArray();
        Assert.False(PageHistory.Holds([.. entries, new(Guid.NewGuid(), "https://overflow.example/", "Overflow")], 0));
        history.Report(entries, entries.Length - 1);
        history.Reopen(restores: false);
        history.Report([entries[^1] with { Id = Guid.NewGuid() }], 0);
        Assert.Equal(PageHistory.Capacity, history.Entries.Count);
        Assert.Equal(entries.Length - 1, history.Back.Count);
        var navigated = Enumerable.Range(0, PageHistory.Capacity)
            .Select(index => new PageHistoryEntry(Guid.NewGuid(), $"https://new.example/{index}", $"New {index}")).ToArray();
        history.Report(navigated, navigated.Length - 1);
        Assert.Equal(navigated, history.Entries);
        Assert.Equal(PageHistory.Capacity - 1, history.Back.Count);
    }

    private static PageHistoryEntry[] HistoryEntries() => [
        new(Guid.NewGuid(), "https://history.example/one", "One"),
        new(Guid.NewGuid(), "https://history.example/two", "Two"),
        new(Guid.NewGuid(), "https://history.example/three", "Three")
    ];

    private static void CommitHistory(CrestApp app, Engine engine, Guid page, PageHistoryEntry[] entries) {
        app.Report(engine, new NavigationCommitted(page, entries[1].Url, SameDocument: false));
        app.Report(engine, new NavigationFinished(page, entries[1].Url, entries[1].Title));
        app.Report(engine, new PageStateChanged(page, Showing(entries[1].Url, entries[1].Title)));
        app.Report(engine, new PageHistoryReported(page, entries, 1));
    }
}
