using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Where a lift in a window's sidebar may drop, what each drop commits, and
/// the queries a window asks about a selection and "Split With Next Tab".
public sealed partial class BrowserContractsTests {
    /// The rule that refuses dropping `selection` at the end of the list of
    /// `section` or `folder`, as a lift reaching that list asks it.
    private static Rejection? ListRefusal(TestDevice device, Guid window, Guid space, TabSelection selection, TabPlacement section,
        Guid? folder) =>
        device.Query(new CanSend(new DropIntoList(device.Workspace, window, space, selection, section, folder, BeforeTabId: null,
            BeforeFolderId: null))).Refusal;

    /// The rule that refuses dropping `selection` on the Space `destination`.
    private static Rejection? SpaceRefusal(TestDevice device, Guid window, Guid space, TabSelection selection, Guid destination) =>
        device.Query(new CanSend(new DropOnSpace(device.Workspace, window, space, selection, destination, Follows: false))).Refusal;

    /// One tab lifted alone drops everywhere dragging one tab could: among the
    /// pinned tabs, on another Space, on the cards a window shows and around an
    /// open tab, even from a split, which it leaves.
    [Fact]
    public void ALoneTabDropsWhereDraggingOneTabCouldAndLeavesItsSplit() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        var targets = device.Query(new DropTargets(device.Workspace, window, f.Space, Picking(f.A)));

        Assert.Null(targets.Refusal);
        Assert.Equal(3 + 3, targets.Lists.Count);
        Assert.All(targets.Lists, list => Assert.Null(ListRefusal(device, window, f.Space, Picking(f.A), list.Section, list.FolderId)));
        Assert.Equal([f.Second, f.Third], targets.SpaceIds);
        Assert.All(targets.SpaceIds, space => Assert.Null(SpaceRefusal(device, window, f.Space, Picking(f.A), space)));
        Assert.Equal(new SplitDropTarget(f.C1, Refusal: null), targets.Split);
        Assert.Equal([f.C1, f.C2, f.C5], targets.FolderAroundTabIds);

        device.Send(new DropAroundTab(device.Workspace, window, f.Space, Picking(f.A), f.C1));
        var space = device.Authority.Current.Spaces[0];
        var folder = space.Tabs.Single(tab => tab.Id == f.A).FolderId;
        Assert.NotNull(folder);
        Assert.Equal([f.C1, f.A], space.Tabs.Where(tab => tab.FolderId == folder).Select(tab => tab.Id));
        Assert.Null(space.Tabs.Single(tab => tab.Id == f.A).SplitGroupId);
    }

    /// Any other lift drops as the batch intents act on a selection, and the
    /// drag keeps pinned tabs apart: they lift only with pinned tabs, move one
    /// at a time into the pinned tabs, and several stay in their Space and out
    /// of the cards a window shows. A folder never drops into itself.
    [Fact]
    public void ASelectionDropsWhereTheBatchIntentsAndTheDragRulesAllow() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C5));
        DropTargetList Targets(TabSelection selection) => device.Query(new DropTargets(device.Workspace, window, f.Space, selection));

        var two = Picking(f.C1, f.C2);
        var open = Targets(two);
        Assert.IsType<PinsOneTabAtATime>(ListRefusal(device, window, f.Space, two, TabPlacement.Pinned, null));
        Assert.All(open.Lists.Where(list => list.Section != TabPlacement.Pinned),
            list => Assert.Null(ListRefusal(device, window, f.Space, two, list.Section, list.FolderId)));
        Assert.All(open.SpaceIds, space => Assert.Null(SpaceRefusal(device, window, f.Space, two, space)));
        Assert.Null(open.Split!.Refusal);
        Assert.Equal([f.C5], open.FolderAroundTabIds);

        var pins = Picking(f.P1, f.P2);
        var pinned = Targets(pins);
        Assert.Null(ListRefusal(device, window, f.Space, pins, TabPlacement.Pinned, null));
        Assert.Null(ListRefusal(device, window, f.Space, pins, TabPlacement.Saved, null));
        Assert.All(pinned.SpaceIds, space => Assert.IsType<PinnedTabsStayPut>(SpaceRefusal(device, window, f.Space, pins, space)));
        Assert.IsType<PinnedTabsStayPut>(pinned.Split!.Refusal);

        var mixed = Targets(Picking(f.P1, f.C1));
        Assert.IsType<PinnedTabsDragAlone>(mixed.Refusal);
        Assert.Empty(mixed.Lists);

        TabSelection lifted = new([], [f.Open], [f.C3]);
        var folder = Targets(lifted);
        Assert.IsType<PinsOneTabAtATime>(ListRefusal(device, window, f.Space, lifted, TabPlacement.Pinned, null));
        Assert.Equal(new FolderCycle(f.Open), ListRefusal(device, window, f.Space, lifted, TabPlacement.Current, f.Open));
        Assert.Null(ListRefusal(device, window, f.Space, lifted, TabPlacement.Current, f.Shut));
        Assert.Null(ListRefusal(device, window, f.Space, lifted, TabPlacement.Saved, f.Kept));
        Assert.All(folder.SpaceIds, space => Assert.IsType<SelectionHoldsFolders>(SpaceRefusal(device, window, f.Space, lifted, space)));
        Assert.IsType<SelectionHoldsFolders>(folder.Split!.Refusal);
        Assert.Empty(folder.FolderAroundTabIds);

        // A window that no longer shows the Space refuses the lift itself.
        device.Send(new ShowSpace(window, f.Second));
        Assert.IsType<SelectionChanged>(Targets(Picking(f.C1)).Refusal);
    }

    /// A full pinned area refuses another tab and still reorders its own.
    [Fact]
    public void AFullPinnedAreaRefusesAnotherTabAndStillReorders() {
        var f = new OrderSpace(extraPinned: TabPlacement.PinnedCapacity - 2);
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        Assert.Equal(new PinnedTabsFull(TabPlacement.PinnedCapacity),
            ListRefusal(device, window, f.Space, Picking(f.C1), TabPlacement.Pinned, null));
        Assert.Null(ListRefusal(device, window, f.Space, Picking(f.P1), TabPlacement.Pinned, null));
    }

    /// A whole split dropped on a collapsed folder's row goes to the end of its
    /// inside and stays one split row there, hidden while the folder is collapsed.
    [Fact]
    public void AWholeSplitDropsOntoACollapsedFolderAndStaysOneSplitRow() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.A));
        var split = Picking(f.A, f.B);

        Assert.Null(ListRefusal(device, window, f.Space, split, TabPlacement.Current, f.Shut));
        device.Send(new DropIntoList(device.Workspace, window, f.Space, split, TabPlacement.Current, f.Shut, BeforeTabId: null,
            BeforeFolderId: null));

        var space = device.Authority.Current.Spaces[0];
        var inside = space.Sidebar.Lists.Single(list => list.FolderId == f.Shut).Rows;
        Assert.Equal([f.C4, f.Split], inside.Select(row => row.Id));
        Assert.Same(SidebarRowKind.Split, inside[1].Kind);
        Assert.Equal([f.A, f.B], inside[1].Members);
        Assert.True(space.Folders.Single(folder => folder.Id == f.Shut).IsCollapsed);
        Assert.DoesNotContain(space.Stops(), stop => stop.Id == f.Split);
    }

    /// "Split With Next Tab" adds the next tab row in the shown tab's own list
    /// that is in no split, skipping a split's tabs rather than taking them, and
    /// a pinned neighbour, which joins as a copy; there is none after the last
    /// row, for a Start Page, or when the split is full.
    [Theory]
    [InlineData(nameof(OrderSpace.A), nameof(OrderSpace.C2))]
    [InlineData(nameof(OrderSpace.C1), nameof(OrderSpace.C2))]
    [InlineData(nameof(OrderSpace.P1), nameof(OrderSpace.P2))]
    [InlineData(nameof(OrderSpace.C5), null)]
    [InlineData(nameof(OrderSpace.C3), null)]
    [InlineData(nameof(OrderSpace.N), null)]
    public void SplitWithNextTabAddsTheNextFreeTabRowInTheShownTabsList(string shown, string? candidate) {
        var f = new OrderSpace();
        Guid Named(string name) => (Guid)typeof(OrderSpace).GetProperty(name)!.GetValue(f)!;
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, Named(shown)));

        Assert.Equal(candidate is null ? null : Named(candidate), device.Query(new SplitJoinCandidate(window)).TabId);
    }

    [Fact]
    public void SplitWithNextTabAddsNothingToAFullSplit() {
        var f = new OrderSpace(extraMembers: 2);
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.A));

        Assert.Null(device.Query(new SplitJoinCandidate(window)).TabId);
    }

    /// A preview holds the picks no picked folder holds, in sidebar order, and
    /// every tab and folder they hold, leaving out a Start Page and a pick the
    /// Space does not hold; its selection is one the batch intents take.
    [Fact]
    public void APreviewHoldsThePicksAndWhatTheyHoldInSidebarOrder() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        var preview = device.Query(new SelectionPreview(device.Workspace, f.Space, [f.C3, f.C5, f.N, Guid.NewGuid(), f.C1], [f.Open]));

        Assert.Equal([(f.C1, SidebarRowKind.Tab), (f.Open, SidebarRowKind.Folder), (f.C5, SidebarRowKind.Tab)],
            preview.Roots.Select(root => (root.Id, root.Kind)));
        Assert.Equal([new(f.C1, TabPlacement.Current, null, null), new(f.C3, TabPlacement.Current, f.Open, null),
            new SelectedTab(f.C5, TabPlacement.Current, null, null)], preview.Members);
        Assert.Equal([f.Open], preview.FolderIds);
        Assert.Equal([f.C1, f.C5], preview.Selection.TabIds);
        Assert.Equal([f.Open], preview.Selection.FolderIds);
        Assert.Null(device.Query(new CanSend(new FileTabs(device.Workspace, window, f.Space, preview.Selection, TabPlacement.Saved, null,
            null, null, LeavesSplits: false))).Refusal);
    }
}
