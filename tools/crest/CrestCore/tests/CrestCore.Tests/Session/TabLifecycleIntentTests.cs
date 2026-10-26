using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Opening, closing, deleting, clearing, copying and moving tabs: where a tab
/// lands, what its section refuses, what closing keeps, and which tab a window
/// shows afterwards.
public sealed partial class BrowserContractsTests {
    /// A saved session whose saved tab is an open split member with a partner,
    /// followed by an open tab of its own.
    private static (JsonNode Session, Guid Space, Guid Member, Guid Partner, Guid Plain) SplitSession() {
        var f = SavedSession(); var space = f.Document["session"]!["spaces"]![0]!;
        var group = SwiftId(Guid.NewGuid()); var partner = Guid.NewGuid(); var plain = Guid.NewGuid();
        var first = space["tabs"]![0]!.AsObject();
        first["placement"] = "current"; first["folderID"] = null; first["savedURL"] = null; first["splitGroupID"] = group.DeepClone();
        JsonObject Current(Guid id, JsonNode? split) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = "https://example.org/" + id,
            ["placement"] = "current",
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0,
            ["splitGroupID"] = split
        };
        space["tabs"]!.AsArray().Add(Current(partner, group.DeepClone()));
        space["tabs"]!.AsArray().Add(Current(plain, null));
        return (f.Document["session"]!, f.Space, f.Tab, partner, plain);
    }

    private static TabContent Page(string address, string? title = null) => new(address, View: null, title);

    [Fact]
    public void ClosingArchivesAnOpenTabAndPutsASavedTabsPageAwayReturningTheWindowToItsPreviousTab() {
        using var device = new TestDevice(MaximalDocument());
        var core = device.Authority;
        TestGrants.UnlockGuarded(device.Send, device.Workspace, core.Current);
        var space = core.Current.Spaces[0];
        Guid Id(string value) => Guid.Parse(value);
        Guid left = Id("428CAA9C-9A7A-4386-B120-F6096032C167"), right = Id("942AC076-B0D8-454B-9EEB-3791E6113F77"),
            article = Id("B61250D4-3D4E-4DD6-8871-0BB326669142"), start = Id("056F15C0-13CE-4ED0-B9FE-DD4A9D05A56D");
        var window = device.Open(space.Id);
        foreach (var tab in new[] { start, right, article }) device.Send(new ShowTab(window, space.Id, tab));

        // A saved tab keeps its place, and its page returns to its saved
        // address when the app's preferences say so. The window that asked
        // lets the tab's page go, keeping nothing of it.
        var putAway = device.Send(new CloseTab(device.Workspace, window, space.Id, article)).OfType<TabPagePutAway>();
        var kept = core.Current.Spaces[0].Tabs.Single(tab => tab.Id == article);
        Assert.Equal((TabPlacement.Saved, "https://news.example/article"), (kept.Placement, kept.Url));
        Assert.Equal(right, device.Tab(window, space.Id));
        Assert.Equal([new TabPagePutAway(device.Workspace, window, space.Id, article, KeepsState: false)], putAway);

        // An open tab is archived, and the window goes back to the tab it
        // showed before; no page is put away.
        Assert.Empty(device.Send(new CloseTab(device.Workspace, window, space.Id, right)).OfType<TabPagePutAway>());
        Assert.DoesNotContain(core.Current.Spaces[0].Tabs, tab => tab.Id == right);
        var archived = core.Current.Spaces[0].ArchivedTabs[^1];
        Assert.Equal((right, ArchiveReason.Closed), (archived.Tab.Id, archived.Reason));
        Assert.Null(archived.Tab.SplitGroupId);
        Assert.Equal(start, device.Tab(window, space.Id));
        // Its split partner is left on its own, so the split and its name go.
        Assert.Null(core.Current.Spaces[0].Tabs.Single(tab => tab.Id == left).SplitGroupId);
        Assert.Empty(core.Current.Spaces[0].SplitGroups);
    }

}
