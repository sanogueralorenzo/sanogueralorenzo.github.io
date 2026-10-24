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

    private static Guid[] TabOrder(NativeSessionAuthority core) => [.. core.Current.Spaces[0].Tabs.Select(tab => tab.Id)];

    private static TabContent Page(string address, string? title = null) => new(address, View: null, title);

    [Fact]
    public void AnOpenedTabLandsOutsideTheSplitItOpensFromAndOnlyTheAskingWindowShowsIt() {
        var (session, space, member, partner, plain) = SplitSession();
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Open(space, (space, member));
        var elsewhere = device.Open(space, (space, member));
        OpenTab Opening(Guid id, TabContent content, Guid? after, bool shows = true) =>
            new(device.Workspace, window, space, id, content, TabPlacement.Current, after, shows);

        var opened = Guid.NewGuid();
        device.Send(Opening(opened, Page("https://opened.example/path"), member));
        Assert.Equal([member, partner, opened, plain], TabOrder(core));
        Assert.Equal(opened, device.Tab(window, space));
        Assert.Equal(member, device.Tab(elsewhere, space));
        var tab = core.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == opened);
        Assert.Equal(("opened.example", "https://opened.example/path", "globe"), (tab.Title, tab.Url, tab.Symbol));
        Assert.Null(tab.SavedUrl);

        // An origin outside the Space leaves the tab where its section puts a
        // new one, and a tab that does not show leaves the window as it was.
        var start = Guid.NewGuid();
        device.Send(Opening(start, new TabContent(null, null, null), Guid.NewGuid(), shows: false));
        Assert.Equal(start, TabOrder(core)[0]);
        Assert.Equal(opened, device.Tab(window, space));
        var startPage = core.Current.Spaces[0].Tabs[0];
        Assert.Equal(("Start Page", "flag.fill", (string?)null), (startPage.Title, startPage.Symbol, startPage.Url));

        Assert.Equal("not an address", Assert.IsType<UnsupportedAddress>(Assert.Throws<Rejected>(() =>
            device.Send(Opening(Guid.NewGuid(), Page("not an address"), null))).Rejection).Url);
        Assert.Equal(opened, Assert.IsType<TabAlreadyExists>(Assert.Throws<Rejected>(() =>
            device.Send(Opening(opened, Page("https://again.example/"), null))).Rejection).TabId);
    }

    [Fact]
    public void AWindowShowsTheSplitItsTabIsInAsCardsAndATabOutsideOneAlone() {
        var (session, space, member, partner, plain) = SplitSession();
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, member));

        var split = device.Shown(window).Cards.Single(cards => cards.SpaceId == space);
        Assert.Equal([member, partner], split.TabIds);
        Assert.NotNull(split.SplitGroupId);
        Assert.DoesNotContain(ShortcutCommand.SeparateSplitTabs, device.Shown(window).UnavailableCommands);

        device.Send(new ShowTab(window, space, plain));
        var alone = device.Shown(window).Cards.Single(cards => cards.SpaceId == space);
        Assert.Equal([plain], alone.TabIds);
        Assert.Null(alone.SplitGroupId);
        Assert.Contains(ShortcutCommand.SeparateSplitTabs, device.Shown(window).UnavailableCommands);
    }

    [Fact]
    public void TheSpacesPinnedTabsStopAtTheirCapacity() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        for (var index = 0; index < TabPlacement.PinnedCapacity; index++)
            space["tabs"]!.AsArray().Add(new JsonObject {
                ["id"] = SwiftId(Guid.NewGuid()),
                ["title"] = "Pinned",
                ["url"] = $"https://pinned{index}.example/",
                ["placement"] = "pinned",
                ["symbol"] = "globe",
                ["lastActivatedAt"] = 800000000.0
            });
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Open(f.Space);
        var full = core.Current;

        void Refused(Intent intent) =>
            Assert.Equal(TabPlacement.PinnedCapacity, Assert.IsType<PinnedTabsFull>(Assert.Throws<Rejected>(() => device.Send(intent))
                .Rejection).Capacity);
        Refused(new OpenTab(device.Workspace, window, f.Space, Guid.NewGuid(), Page("https://one-more.example/"), TabPlacement.Pinned,
            null, true));
        Refused(new MoveTab(device.Workspace, f.Space, f.Tab, TabPlacement.Pinned, null, null, LeavesSplit: true));
        Refused(new DuplicateTab(device.Workspace, window, f.Space, f.Tab, TabPlacement.Pinned, true));
        Assert.IsType<PinnedTabsFull>(device.Query(new CanSend(new MoveTab(device.Workspace, f.Space, f.Tab, TabPlacement.Pinned, null,
            null, LeavesSplit: true))).Refusal);
        Assert.Same(full, core.Current);
    }

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

    [Fact]
    public void TheStartPageThatIsItsSpacesOnlyTabLeavesOnlyItsWindowToClose() {
        var f = SavedSession(); var session = f.Document["session"]!; var tab = session["spaces"]![0]!["tabs"]![0]!.AsObject();
        tab["placement"] = "current"; tab["url"] = null; tab["savedURL"] = null; tab["folderID"] = null; tab["splitGroupID"] = null;
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Tab));
        var closing = new CloseTab(device.Workspace, window, f.Space, f.Tab);

        Assert.Equal(f.Tab, Assert.IsType<LastStartPage>(device.Query(new CanSend(closing)).Refusal).TabId);
        Assert.IsType<LastStartPage>(Assert.Throws<Rejected>(() => device.Send(closing)).Rejection);
        // Beside another tab it closes, and a Start Page is never archived.
        device.Send(new OpenTab(device.Workspace, window, f.Space, Guid.NewGuid(), Page("https://other.example/"), TabPlacement.Current,
            null, false));
        Assert.Null(device.Query(new CanSend(closing)).Refusal);
        device.Send(closing);
        Assert.DoesNotContain(core.Current.Spaces[0].Tabs, candidate => candidate.Id == f.Tab);
        Assert.Empty(core.Current.Spaces[0].ArchivedTabs);
        Assert.Equal(f.Tab, Assert.IsType<UnknownTab>(Assert.Throws<Rejected>(() => device.Send(closing)).Rejection).TabId);
    }

    [Fact]
    public void DeletingArchivesATabAsAnOpenOneAndClearingArchivesOnlyOpenTabs() {
        using var device = new TestDevice(MaximalDocument());
        var core = device.Authority;
        TestGrants.UnlockGuarded(device.Send, device.Workspace, core.Current);
        var space = core.Current.Spaces[0];
        var article = Guid.Parse("B61250D4-3D4E-4DD6-8871-0BB326669142");
        var window = device.Open(space.Id, (space.Id, article));

        device.Send(new DeleteTab(device.Workspace, window, space.Id, article));
        var deleted = core.Current.Spaces[0].ArchivedTabs[^1];
        Assert.Equal((article, ArchiveReason.Deleted, TabPlacement.Current), (deleted.Tab.Id, deleted.Reason, deleted.Tab.Placement));
        Assert.Equal(((Guid?)null, (string?)null), (deleted.Tab.FolderId, deleted.Tab.SavedUrl));
        // A window left with nothing to show there shows the tab its Space falls back to.
        Assert.Equal(space.Tabs.First(tab => tab.Placement == TabPlacement.Current).Id, device.Tab(window, space.Id));

        var archived = core.Current.Spaces[0].ArchivedTabs.Count;
        device.Send(new ClearCurrentTabs(device.Workspace, window, space.Id));
        var cleared = core.Current.Spaces[0];
        Assert.All(cleared.Tabs, tab => Assert.True(tab.Placement.IsDurable));
        // The Start Page among them is not archived.
        Assert.Equal(archived + 2, cleared.ArchivedTabs.Count);
        Assert.Equal(cleared.Tabs[0].Id, device.Tab(window, space.Id));
        Assert.Equal(space.Id, Assert.IsType<NoCurrentTabs>(Assert.Throws<Rejected>(() =>
            device.Send(new ClearCurrentTabs(device.Workspace, window, space.Id))).Rejection).SpaceId);
    }

    [Fact]
    public void ACopyTakesAnIdentityTheCoreGivesAndStartsFromWhatItsSourcesPageShows() {
        var f = SavedSession(); var session = f.Document["session"]!;
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Tab));
        device.ShowPage(window, f.Space, f.Tab, PageSnapshot.Blank with { Url = "https://example.com/live-child", Title = "Live title" });
        var copy = Guid.NewGuid();
        device.Ids.Supply([copy]);

        var copied = Assert.Single(device.Send(new DuplicateTab(device.Workspace, window, f.Space, f.Tab, null, true))
            .OfType<TabCopied>());
        Assert.Equal((device.Workspace, f.Tab, copy), (copied.WorkspaceId, copied.SourceTabId, copied.CopyTabId));
        var tabs = core.Current.Spaces[0].Tabs;
        var original = tabs.Single(tab => tab.Id == f.Tab); var duplicate = tabs.Single(tab => tab.Id == copy);
        Assert.Equal(("https://example.com/live-child", "Live title", "My reading"), (duplicate.Url, duplicate.Title, duplicate.CustomTitle));
        Assert.Equal((TabPlacement.Current, (Guid?)null, (Guid?)null, (string?)null),
            (duplicate.Placement, duplicate.FolderId, duplicate.SplitGroupId, duplicate.SavedUrl));
        Assert.Equal(original.IconAccent, duplicate.IconAccent);
        Assert.Equal((TabPlacement.Saved, "https://example.com/article#one"), (original.Placement, original.Url));
        Assert.Equal(copy, device.Tab(window, f.Space));
    }

    [Fact]
    public void AMoveTakesATabOutOfItsSplitWhereNoSplitGoesAndRefusesAFolderOutsideItsSection() {
        var (session, space, member, partner, _) = SplitSession();
        var folders = session["spaces"]![0]!["folders"]!.AsArray();
        var saved = Guid.Parse(folders[0]!["id"]!["rawValue"]!.GetValue<string>());
        using var device = new TestDevice(session);
        var core = device.Authority;
        MoveTab Moving(TabPlacement placement, Guid? folder = null, bool leaves = false) =>
            new(device.Workspace, space, member, placement, folder, null, leaves);
        var before = core.Current;

        Assert.IsType<InvalidFolderPlacement>(Assert.Throws<Rejected>(() => device.Send(Moving(TabPlacement.Current, saved))).Rejection);
        var missing = Guid.NewGuid();
        Assert.Equal(missing, Assert.IsType<UnknownFolder>(Assert.Throws<Rejected>(() =>
            device.Send(Moving(TabPlacement.Saved, missing))).Rejection).FolderId);
        Assert.Same(before, core.Current);

        // Pinned tabs keep no splits: the tab pins out of its split, and its
        // partner is a split no more.
        device.Send(Moving(TabPlacement.Pinned));
        var tabs = core.Current.Spaces[0].Tabs;
        Assert.Equal((TabPlacement.Pinned, (Guid?)null), (tabs[0].Placement, tabs[0].SplitGroupId));
        Assert.Equal(member, tabs[0].Id);
        Assert.Null(tabs.Single(tab => tab.Id == partner).SplitGroupId);
        device.Send(Moving(TabPlacement.Saved, saved));
        Assert.Equal((TabPlacement.Saved, (Guid?)saved), (core.Current.Spaces[0].Tabs.Single(tab => tab.Id == member).Placement,
            core.Current.Spaces[0].Tabs.Single(tab => tab.Id == member).FolderId));
    }
}
