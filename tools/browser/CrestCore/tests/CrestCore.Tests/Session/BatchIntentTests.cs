using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Intents on the tabs and folders a person selected together: what each
/// does, which tab the window shows afterwards, and the rules that refuse a
/// selection, which change nothing.
public sealed partial class BrowserContractsTests {
    /// A session whose first Space holds, in order, a pinned tab, a saved tab
    /// in a saved folder, three open tabs of which the last two are a split,
    /// an open tab, and an open tab in an open folder; its second Space holds
    /// one open tab.
    private sealed class BatchSpace {
        public Guid Space { get; } = Guid.NewGuid();
        public Guid Other { get; } = Guid.NewGuid();
        public Guid Pinned { get; } = Guid.NewGuid();
        public Guid Saved { get; } = Guid.NewGuid();
        public Guid Open { get; } = Guid.NewGuid();
        public Guid Left { get; } = Guid.NewGuid();
        public Guid Right { get; } = Guid.NewGuid();
        public Guid Last { get; } = Guid.NewGuid();
        public Guid Filed { get; } = Guid.NewGuid();
        public Guid Resident { get; } = Guid.NewGuid();
        public Guid SavedFolder { get; } = Guid.NewGuid();
        public Guid OpenFolder { get; } = Guid.NewGuid();
        public Guid Split { get; } = Guid.NewGuid();
        public JsonNode Session { get; }

        public BatchSpace() {
            var fixture = SavedSession();
            Session = fixture.Document["session"]!;
            Session.AsObject().Remove("disposableSeedMarker");
            var space = Session["spaces"]![0]!.AsObject();
            space["id"] = SwiftId(Space);
            space["tabs"] = new JsonArray(Tab(Pinned, "pinned"), Tab(Saved, "saved", SavedFolder), Tab(Open, "current"),
                Tab(Left, "current", split: Split), Tab(Right, "current", split: Split), Tab(Last, "current"),
                Tab(Filed, "current", OpenFolder));
            space["folders"] = new JsonArray(Folder(SavedFolder, "saved"), Folder(OpenFolder, "current"));
            space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = Split.ToString(), ["customTitle"] = "Research" });
            space.Remove("selectedTabID");
            var other = space.DeepClone().AsObject();
            other["id"] = SwiftId(Other);
            other["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString() };
            other["tabs"] = new JsonArray(Tab(Resident, "current"));
            other["folders"] = new JsonArray();
            other["splitGroups"] = new JsonArray();
            other["history"] = new JsonArray();
            Session["spaces"]!.AsArray().Add(other);
            Session.AsObject().Remove("selectedSpaceID");
        }

        private static JsonObject Tab(Guid id, string placement, Guid? folder = null, Guid? split = null) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = $"https://batch.example/{id}",
            ["placement"] = placement,
            ["savedURL"] = placement == "current" ? null : $"https://batch.example/{id}",
            ["folderID"] = folder is { } folderId ? SwiftId(folderId) : null,
            ["splitGroupID"] = split is { } group ? SwiftId(group) : null,
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0
        };

        private static JsonObject Folder(Guid id, string location) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Folder",
            ["location"] = location
        };
    }

    /// The selection of `tabs`, as the window saw it.
    private static TabSelection Picking(params Guid[] tabs) => new(tabs, [], tabs);

    private static Guid[] Tabs(NativeSessionAuthority core, int space = 0) => [.. core.Current.Spaces[space].Tabs.Select(tab => tab.Id)];

    [Fact]
    public void ClosingASelectionArchivesItsOpenTabsAndTheWindowReturnsToTheTabItShowedBefore() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Last));
        device.Send(new ShowTab(window, f.Space, f.Open));
        var before = core.Current;

        CloseTabs Closing(TabSelection selection) => new(device.Workspace, window, f.Space, selection);
        Assert.Equal(f.Saved, Assert.IsType<CurrentTabsOnly>(Assert.Throws<Rejected>(() =>
            device.Send(Closing(Picking(f.Open, f.Saved)))).Rejection).TabId);
        Assert.Equal(f.Split, Assert.IsType<IncompleteSplit>(device.Query(new CanSend(Closing(Picking(f.Left)))).Refusal).GroupId);
        Assert.IsType<SelectionHoldsFolders>(Assert.Throws<Rejected>(() =>
            device.Send(Closing(new([], [f.OpenFolder], [f.Filed])))).Rejection);
        Assert.Same(before, core.Current);

        device.Send(Closing(Picking(f.Right, f.Open, f.Left)));
        Assert.Equal([f.Pinned, f.Saved, f.Last, f.Filed], Tabs(core));
        var archived = core.Current.Spaces[0].ArchivedTabs;
        Assert.Equal([f.Open, f.Left, f.Right], archived.TakeLast(3).Select(entry => entry.Tab.Id));
        Assert.All(archived.TakeLast(3), entry => Assert.Equal((ArchiveReason.Closed, (Guid?)null), (entry.Reason, entry.Tab.SplitGroupId)));
        Assert.Empty(core.Current.Spaces[0].SplitGroups);
        Assert.Equal(f.Last, device.Tab(window, f.Space));
    }

    [Fact]
    public void DeletingASelectionIsSavedWithItsTombstonesBeforeItReturns() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));
        var window = device.Open(f.Space, (f.Space, f.Saved));
        var staged = sync.Snapshot;

        device.Send(new DeleteTabs(device.Workspace, window, f.Space, Picking(f.Saved, f.Pinned)));
        // The deletion staged with the intent, not once edits paused.
        Assert.NotSame(staged, sync.Snapshot);
        var deleted = core.Current.Spaces[0].ArchivedTabs.TakeLast(2).ToArray();
        Assert.Equal([f.Pinned, f.Saved], deleted.Select(entry => entry.Tab.Id));
        Assert.All(deleted, entry => Assert.Equal((ArchiveReason.Deleted, TabPlacement.Current, (Guid?)null),
            (entry.Reason, entry.Tab.Placement, entry.Tab.FolderId)));
        // The window showed a deleted tab, and returns to the one it opened on.
        Assert.Equal(f.Open, device.Tab(window, f.Space));
        var records = JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray();
        foreach (var id in new[] { f.Saved, f.Pinned }) {
            var record = records.Single(record => record!["id"]!["kind"]!.GetValue<string>() == "tab"
                && Guid.Parse(record["id"]!["value"]!.GetValue<string>()) == id)!;
            Assert.Equal("explicitDelete", record["tombstone"]!["reason"]!.GetValue<string>());
        }
    }

    [Fact]
    public void CopiesOfASelectionStartFromTheirPagesAndKeepTheirSplitTogether() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Left));
        device.ShowPage(window, f.Space, f.Left, PageSnapshot.Blank with { Url = "https://batch.example/live", Title = "Live" });
        Guid leftCopy = Guid.NewGuid(), rightCopy = Guid.NewGuid(), savedCopy = Guid.NewGuid(), splitCopy = Guid.NewGuid();
        device.Ids.Supply([savedCopy, leftCopy, rightCopy, splitCopy]);

        var copied = device.Send(new DuplicateTabs(device.Workspace, window, f.Space, Picking(f.Right, f.Left, f.Saved)))
            .OfType<TabCopied>().ToArray();

        // The copies come in the order the sidebar lists their sources, at the
        // end of the open tabs, and the window keeps what it showed.
        Assert.Equal([(f.Saved, savedCopy), (f.Left, leftCopy), (f.Right, rightCopy)],
            copied.Select(copy => (copy.SourceTabId, copy.CopyTabId)));
        Assert.Equal([f.Pinned, f.Saved, f.Open, f.Left, f.Right, f.Last, f.Filed, savedCopy, leftCopy, rightCopy], Tabs(core));
        var space = core.Current.Spaces[0];
        var left = space.Tabs.Single(tab => tab.Id == leftCopy);
        Assert.Equal(("https://batch.example/live", "Live"), (left.Url, left.Title));
        Assert.Equal($"https://batch.example/{f.Right}", space.Tabs.Single(tab => tab.Id == rightCopy).Url);
        var saved = space.Tabs.Single(tab => tab.Id == savedCopy);
        Assert.Equal((TabPlacement.Current, (Guid?)null, (string?)null), (saved.Placement, saved.FolderId, saved.SavedUrl));
        Assert.Equal((splitCopy, splitCopy), (left.SplitGroupId, space.Tabs.Single(tab => tab.Id == rightCopy).SplitGroupId));
        Assert.Equal("Research", space.SplitGroups.Single(group => group.Id == splitCopy).CustomTitle);
        Assert.Equal(f.Left, device.Tab(window, f.Space));
    }

    [Fact]
    public void ASelectionCombinesInOneSplitOfTwoToFourTabs() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        SplitTabs Splitting(TabSelection selection, Guid? target = null) => new(device.Workspace, window, f.Space, selection, target, null);
        var before = core.Current;

        Assert.Equal(BrowserTabCollectionLimit, Assert.IsType<SplitNeedsTwoTabs>(Assert.Throws<Rejected>(() =>
            device.Send(Splitting(Picking(f.Open)))).Rejection).Limit);
        Assert.Equal(BrowserTabCollectionLimit, Assert.IsType<SplitLimitReached>(device.Query(new CanSend(
            Splitting(Picking(f.Open, f.Last, f.Filed), f.Left))).Refusal).Limit);
        Assert.Same(before, core.Current);

        // A saved tab stays where it is and an open copy joins in its place.
        var copy = Guid.NewGuid();
        device.Ids.Supply([copy]);
        var copied = Assert.Single(device.Send(Splitting(Picking(f.Saved, f.Open), f.Left)).OfType<TabCopied>());
        Assert.Equal((f.Saved, copy), (copied.SourceTabId, copied.CopyTabId));
        var space = core.Current.Spaces[0];
        Assert.Equal([f.Pinned, f.Saved, f.Left, f.Right, copy, f.Open, f.Last, f.Filed], Tabs(core));
        Assert.All(new[] { f.Left, f.Right, copy, f.Open }, id => Assert.Equal(f.Split, space.Tabs.Single(tab => tab.Id == id).SplitGroupId));
        Assert.Equal(f.Open, device.Tab(window, f.Space));
    }

    [Fact]
    public void MovingASelectionToAnotherSpaceKeepsItsOrderAndFollowsOnlyWhenAsked() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Last));
        device.Send(new ShowTab(window, f.Space, f.Open));
        MoveTabsToSpace Moving(TabSelection selection, Guid destination, bool follows) =>
            new(device.Workspace, window, f.Space, selection, destination, follows);
        var before = core.Current;

        Assert.Equal(f.Left, Assert.IsType<CannotMoveSplitAcrossSpaces>(Assert.Throws<Rejected>(() =>
            device.Send(Moving(Picking(f.Left, f.Right), f.Other, false))).Rejection).TabId);
        Assert.Equal(f.Space, Assert.IsType<AlreadyInSpace>(device.Query(new CanSend(
            Moving(Picking(f.Open), f.Space, false))).Refusal).SpaceId);
        Assert.Same(before, core.Current);

        // The window gives up the tab it showed for the one it showed before.
        device.Send(Moving(Picking(f.Filed, f.Open), f.Other, follows: false));
        Assert.Equal([f.Resident, f.Open, f.Filed], Tabs(core, 1));
        Assert.Null(core.Current.Spaces[1].Tabs.Single(tab => tab.Id == f.Filed).FolderId);
        Assert.Equal((f.Space, (Guid?)f.Last), (device.Space(window), device.Tab(window, f.Space)));
        Assert.DoesNotContain(core.Current.Spaces[0].Tabs, tab => tab.Id == f.Open || tab.Id == f.Filed);

        // Following, it shows the tab it showed there, which moved.
        device.Send(Moving(Picking(f.Last, f.Pinned), f.Other, follows: true));
        Assert.Equal([f.Pinned, f.Resident, f.Open, f.Filed, f.Last], Tabs(core, 1));
        Assert.Equal((f.Other, (Guid?)f.Last), (device.Space(window), device.Tab(window, f.Other)));
        Assert.Null(device.Tab(window, f.Space));
    }

    [Fact]
    public void AMoveToAFullPinnedSectionRefusesTheWholeSelection() {
        var f = new BatchSpace();
        var other = f.Session["spaces"]![1]!["tabs"]!.AsArray();
        for (var index = 0; index < TabPlacement.PinnedCapacity; index++)
            other.Add(new JsonObject {
                ["id"] = SwiftId(Guid.NewGuid()),
                ["title"] = "Pinned",
                ["url"] = $"https://pinned{index}.example/",
                ["savedURL"] = $"https://pinned{index}.example/",
                ["placement"] = "pinned",
                ["symbol"] = "globe",
                ["lastActivatedAt"] = 800000000.0
            });
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        var before = core.Current;

        Assert.Equal(TabPlacement.PinnedCapacity, Assert.IsType<PinnedTabsFull>(Assert.Throws<Rejected>(() =>
            device.Send(new MoveTabsToSpace(device.Workspace, window, f.Space, Picking(f.Open, f.Pinned), f.Other, false))).Rejection)
            .Capacity);
        Assert.Same(before, core.Current);
    }

    [Fact]
    public void FilingASelectionMovesItsFoldersWholeInTheOrderTheSidebarListsThem() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        FileTabs Filing(TabSelection selection, TabPlacement placement, Guid? folder = null) =>
            new(device.Workspace, window, f.Space, selection, placement, folder, null, null, LeavesSplits: false);
        // The sidebar lists the tab before the open folder, which takes the
        // place of its first tab.
        var selection = new TabSelection([f.Last], [f.OpenFolder], [f.Filed, f.Last]);
        var before = core.Current;

        Assert.Equal(f.OpenFolder, Assert.IsType<FolderCycle>(Assert.Throws<Rejected>(() =>
            device.Send(Filing(selection, TabPlacement.Current, f.OpenFolder))).Rejection).FolderId);
        Assert.IsType<InvalidFolderPlacement>(device.Query(new CanSend(Filing(selection, TabPlacement.Pinned))).Refusal);
        Assert.Same(before, core.Current);

        device.Send(Filing(selection, TabPlacement.Saved, f.SavedFolder));
        var space = core.Current.Spaces[0];
        Assert.Equal([f.Pinned, f.Saved, f.Last, f.Filed, f.Open, f.Left, f.Right], Tabs(core));
        Assert.Equal((TabPlacement.Saved, (Guid?)f.SavedFolder),
            (space.Folders.Single(folder => folder.Id == f.OpenFolder).Location, space.Folders.Single(folder => folder.Id == f.OpenFolder).ParentId));
        Assert.Equal((Guid?)f.SavedFolder, space.Tabs.Single(tab => tab.Id == f.Last).FolderId);
        Assert.Equal((Guid?)f.OpenFolder, space.Tabs.Single(tab => tab.Id == f.Filed).FolderId);

        // Pinning moves the tabs one by one, and a split stays out of the pins.
        Assert.Equal(f.Left, Assert.IsType<CannotPinSplit>(Assert.Throws<Rejected>(() =>
            device.Send(Filing(Picking(f.Left, f.Right), TabPlacement.Pinned))).Rejection).TabId);
        device.Send(Filing(Picking(f.Open), TabPlacement.Pinned));
        Assert.Equal([f.Pinned, f.Open], core.Current.Spaces[0].Tabs.Where(tab => tab.Placement == TabPlacement.Pinned).Select(tab => tab.Id));
    }

    [Fact]
    public void PinningASelectionCountsOnlyTheTabsItAddsAndASplitFiledTogetherStaysOne() {
        var f = new BatchSpace();
        var tabs = f.Session["spaces"]![0]!["tabs"]!.AsArray();
        Guid[] pins = [.. Enumerable.Range(0, TabPlacement.PinnedCapacity - 2).Select(_ => Guid.NewGuid())];
        foreach (var pin in pins)
            tabs.Insert(1, new JsonObject {
                ["id"] = SwiftId(pin),
                ["title"] = "Pinned",
                ["url"] = $"https://batch.example/{pin}",
                ["savedURL"] = $"https://batch.example/{pin}",
                ["placement"] = "pinned",
                ["symbol"] = "globe",
                ["lastActivatedAt"] = 800000000.0
            });
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        FileTabs Filing(TabSelection selection, TabPlacement placement, Guid? folder = null, Guid? before = null) =>
            new(device.Workspace, window, f.Space, selection, placement, folder, before, null, LeavesSplits: false);
        var before = core.Current;

        // One pinned slot is left, and two open tabs would need two.
        Assert.Equal(TabPlacement.PinnedCapacity, Assert.IsType<PinnedTabsFull>(Assert.Throws<Rejected>(() =>
            device.Send(Filing(Picking(f.Open, f.Last), TabPlacement.Pinned))).Rejection).Capacity);
        Assert.Same(before, core.Current);
        // Reordering pinned tabs takes no slot of its own.
        device.Send(Filing(Picking(f.Pinned, pins[0]), TabPlacement.Pinned, before: pins[^1]));
        var pinned = core.Current.Spaces[0].Tabs.Where(tab => tab.Placement == TabPlacement.Pinned).Select(tab => tab.Id).ToArray();
        Assert.Equal(TabPlacement.PinnedCapacity - 1, pinned.Length);
        Assert.Equal([f.Pinned, pins[0], pins[^1]], pinned[..3]);

        device.Send(Filing(Picking(f.Left, f.Right), TabPlacement.Saved, f.SavedFolder));
        var space = core.Current.Spaces[0];
        Assert.Equal([f.Saved, f.Left, f.Right], space.Tabs.Where(tab => tab.FolderId == f.SavedFolder).Select(tab => tab.Id));
        Assert.All(space.Tabs.Where(tab => tab.Id == f.Left || tab.Id == f.Right), tab => Assert.Equal(f.Split, tab.SplitGroupId));
    }

    [Fact]
    public void ANewFolderForASelectionTakesTheDefaultColorAndCanStandInATabsPlace() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        Guid made = Guid.NewGuid(), around = Guid.NewGuid();

        device.Ids.Supply([made]);
        device.Send(new FolderTabs(device.Workspace, window, f.Space, new([f.Pinned], [f.SavedFolder], [f.Saved, f.Pinned]),
            TabPlacement.Saved));
        var space = core.Current.Spaces[0];
        var folder = space.Folders.Single(candidate => candidate.Id == made);
        Assert.Equal(("New Folder", FolderState.DefaultColor, (Guid?)null), (folder.Title, folder.Color, folder.ParentId));
        Assert.Equal((Guid?)made, space.Folders.Single(candidate => candidate.Id == f.SavedFolder).ParentId);
        Assert.Equal(((Guid?)made, TabPlacement.Saved), (space.Tabs.Single(tab => tab.Id == f.Pinned).FolderId,
            space.Tabs.Single(tab => tab.Id == f.Pinned).Placement));

        FolderTabsAround Wrapping(Guid tab) => new(device.Workspace, window, f.Space, Picking(f.Last), tab);
        Assert.IsType<InvalidFolderPlacement>(Assert.Throws<Rejected>(() => device.Send(Wrapping(f.Left))).Rejection);
        Assert.IsType<InvalidFolderPlacement>(device.Query(new CanSend(Wrapping(f.Filed))).Refusal);
        device.Ids.Supply([around]);
        device.Send(Wrapping(f.Open));
        space = core.Current.Spaces[0];
        Assert.Equal([f.Open, f.Last], space.Tabs.Where(tab => tab.FolderId == around).Select(tab => tab.Id));
        Assert.Equal((TabPlacement.Current, FolderState.DefaultColor), (space.Folders.Single(candidate => candidate.Id == around).Location,
            space.Folders.Single(candidate => candidate.Id == around).Color));
    }

    [Fact]
    public void ASelectionThatChangedSinceTheWindowSawItIsRefused() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        var elsewhere = device.Open(f.Other);
        KeepTabsLoaded Keeping(TabSelection selection, Guid? from = null) => new(device.Workspace, from ?? window, f.Space, selection, true);
        var before = core.Current;

        // The folder holds a tab the window did not see, a tab is gone, or the
        // window shows another Space.
        Assert.IsType<SelectionChanged>(Assert.Throws<Rejected>(() => device.Send(Keeping(new([], [f.OpenFolder], [])))).Rejection);
        Assert.IsType<SelectionChanged>(device.Query(new CanSend(Keeping(Picking(f.Open, Guid.NewGuid())))).Refusal);
        Assert.IsType<SelectionChanged>(device.Query(new CanSend(Keeping(Picking(f.Open), elsewhere))).Refusal);
        Assert.Same(before, core.Current);

        // A folder's tabs keep their pages loaded with the rest.
        device.Send(Keeping(new([f.Open], [f.OpenFolder], [f.Open, f.Filed])));
        Assert.All(core.Current.Spaces[0].Tabs.Where(tab => tab.Id == f.Open || tab.Id == f.Filed), tab => Assert.True(tab.KeepsPageLoaded));
        device.Send(new SeparateSplits(device.Workspace, window, f.Space, Picking(f.Left, f.Right)));
        Assert.All(core.Current.Spaces[0].Tabs, tab => Assert.Null(tab.SplitGroupId));
    }

    private const int BrowserTabCollectionLimit = CrestCore.Domain.BrowserTabCollection.MaximumSplitMembers;
}
