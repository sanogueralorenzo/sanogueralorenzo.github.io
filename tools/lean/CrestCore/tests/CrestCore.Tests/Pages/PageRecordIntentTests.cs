using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void NativePageRecordsEditTheTabAndVisitAtomicallyWithoutACoreRenderer() {
        using var directory = new StorageDirectory();
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var adopted = app.Send(Adoption(SavedSession().Document["session"]!.AsObject()));
        var (workspace, opened) = TestWorkspaces.OpenStored(app);
        DrainLaunch(app, [.. adopted, .. opened]);
        var authority = app.Workspace(workspace);
        var space = authority.Current.Spaces[0];
        var tab = space.Tabs[0];
        var page = Guid.NewGuid();
        var at = DateTimeOffset.Parse("2026-10-28T12:00:00Z");
        var changes = Own(app.Send(new RecordPageNavigation(workspace, page, space.Id, tab.Id,
            "https://native.example/article#section", "Article", at, Guid.NewGuid(), HasIcon: false, IconAccent: null)));
        Assert.Equal([typeof(TabsChanged), typeof(HistoryChanged), typeof(NavigationRecorded)], changes.Select(change => change.GetType()));
        Assert.Equal(("https://native.example/article#section", "Article", tab.CustomTitle),
            (authority.Current.Spaces[0].Tabs[0].Url, authority.Current.Spaces[0].Tabs[0].Title, authority.Current.Spaces[0].Tabs[0].CustomTitle));
        Assert.Equal(("https://native.example/article", "Article", 1),
            (authority.Current.Spaces[0].History[0].Url, authority.Current.Spaces[0].History[0].Title, authority.Current.Spaces[0].History[0].VisitCount));
        app.Send(new RecordPageTitle(workspace, page, space.Id, tab.Id, "https://native.example/article", "Unread count", at, Visit: false));
        Assert.Equal("Unread count", authority.Current.Spaces[0].Tabs[0].Title);
        Assert.Equal("Article", authority.Current.Spaces[0].History[0].Title);
        app.Send(new RecordPageTitle(workspace, page, space.Id, tab.Id, "https://native.example/article", "Settled title", at, Visit: true));
        Assert.Equal("Settled title", authority.Current.Spaces[0].History[0].Title);
        app.Send(new RecordPageTitle(workspace, page, space.Id, tab.Id, "https://stale.example/", "Stale", at, Visit: true));
        Assert.Equal("Settled title", authority.Current.Spaces[0].Tabs[0].Title);
        app.Send(new CloseWorkspace(workspace));
        Assert.Empty(Own(app.Send(new RecordPageNavigation(workspace, page, space.Id, tab.Id,
            "https://late.example/", "Late", at, Guid.NewGuid(), HasIcon: false, IconAccent: null))));
    }

    [Fact]
    public void NativeTransientPageRecordsOnlyAVisitAndNeverRetargetsAMissingTab() {
        using var directory = new StorageDirectory();
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var adopted = app.Send(Adoption(SavedSession().Document["session"]!.AsObject()));
        var (workspace, opened) = TestWorkspaces.OpenStored(app);
        DrainLaunch(app, [.. adopted, .. opened]);
        var authority = app.Workspace(workspace);
        var space = authority.Current.Spaces[0];
        var original = space.Tabs[0];
        var at = DateTimeOffset.Parse("2026-10-28T12:00:00Z");
        var page = Guid.NewGuid();
        var changes = Own(app.Send(new RecordPageNavigation(workspace, page, space.Id, null,
            "https://transient.example/", "Transient", at, Guid.NewGuid(), HasIcon: false, IconAccent: null)));
        Assert.Equal([typeof(HistoryChanged), typeof(NavigationRecorded)], changes.Select(change => change.GetType()));
        Assert.Equal(original, authority.Current.Spaces[0].Tabs[0]);
        var before = authority.Current;
        Assert.Empty(Own(app.Send(new RecordPageNavigation(workspace, page, space.Id, Guid.NewGuid(),
            "https://missing.example/", "Missing", at, Guid.NewGuid(), HasIcon: true, IconAccent: null))));
        Assert.Equal(before, authority.Current);
    }
}
