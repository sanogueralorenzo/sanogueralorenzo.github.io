using System.Text.Json.Nodes;

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

    /// A session whose first Space holds, in order: pinned tabs P1 and P2, a
    /// saved tab S1 in the collapsed saved folder Kept, a saved tab S2, open tabs
    /// C1, the split A B, the Start Page N, C2, C3 in the open folder Open, C4 in
    /// the collapsed open folder Shut, and C5. Its sidebar shows, in order: P1,
    /// P2, Kept, S2, C1, the split, C2, Open, C3, Shut, C5. Two more Spaces hold
    /// one tab each. `extraPinned` more pinned tabs follow P2, and `extraMembers`
    /// more tabs of the split follow B.
    private sealed class OrderSpace {
        public Guid Space { get; } = Guid.NewGuid();
        public Guid Second { get; } = Guid.NewGuid();
        public Guid Third { get; } = Guid.NewGuid();
        public Guid P1 { get; } = Guid.NewGuid();
        public Guid P2 { get; } = Guid.NewGuid();
        public Guid S1 { get; } = Guid.NewGuid();
        public Guid S2 { get; } = Guid.NewGuid();
        public Guid C1 { get; } = Guid.NewGuid();
        public Guid A { get; } = Guid.NewGuid();
        public Guid B { get; } = Guid.NewGuid();
        public Guid N { get; } = Guid.NewGuid();
        public Guid C2 { get; } = Guid.NewGuid();
        public Guid C3 { get; } = Guid.NewGuid();
        public Guid C4 { get; } = Guid.NewGuid();
        public Guid C5 { get; } = Guid.NewGuid();
        public Guid Kept { get; } = Guid.NewGuid();
        public Guid Open { get; } = Guid.NewGuid();
        public Guid Shut { get; } = Guid.NewGuid();
        public Guid Split { get; } = Guid.NewGuid();
        public Guid SecondTab { get; } = Guid.NewGuid();
        public Guid ThirdTab { get; } = Guid.NewGuid();
        public JsonNode Session { get; }

        /// The tab each stop shows, in order, while the saved section is expanded.
        public Guid[] Stops => [P1, P2, S2, C1, A, C2, C3, C5];

        public OrderSpace(bool savedExpanded = true, int extraPinned = 0, int extraMembers = 0) {
            Session = SavedSession().Document["session"]!;
            Session.AsObject().Remove("disposableSeedMarker");
            Session.AsObject().Remove("selectedSpaceID");
            var space = Session["spaces"]![0]!.AsObject();
            space["id"] = SwiftId(Space);
            space["isSavedTabsExpanded"] = savedExpanded;
            space["tabs"] = new JsonArray([Tab(P1, "pinned"), Tab(P2, "pinned"),
                .. Enumerable.Range(0, extraPinned).Select(_ => Tab(Guid.NewGuid(), "pinned")), Tab(S1, "saved", Kept), Tab(S2, "saved"),
                Tab(C1, "current"), Tab(A, "current", split: Split), Tab(B, "current", split: Split),
                .. Enumerable.Range(0, extraMembers).Select(_ => Tab(Guid.NewGuid(), "current", split: Split)),
                Tab(N, "current", startPage: true), Tab(C2, "current"), Tab(C3, "current", Open), Tab(C4, "current", Shut), Tab(C5, "current")]);
            space["folders"] = new JsonArray(Folder(Kept, "saved", collapsed: true), Folder(Open, "current", collapsed: false),
                Folder(Shut, "current", collapsed: true));
            space["splitGroups"] = new JsonArray();
            space.Remove("selectedTabID");
            Session["spaces"]!.AsArray().Add(Other(space, Second, SecondTab));
            Session["spaces"]!.AsArray().Add(Other(space, Third, ThirdTab));
        }

        private static JsonObject Other(JsonObject first, Guid id, Guid tab) {
            var other = first.DeepClone().AsObject();
            other["id"] = SwiftId(id);
            other["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString() };
            other["tabs"] = new JsonArray(Tab(tab, "current"));
            other["folders"] = new JsonArray();
            other["history"] = new JsonArray();
            return other;
        }

        private static JsonObject Tab(Guid id, string placement, Guid? folder = null, Guid? split = null, bool startPage = false) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = startPage ? null : $"https://order.example/{id}",
            ["placement"] = placement,
            ["savedURL"] = placement == "current" || startPage ? null : $"https://order.example/{id}",
            ["folderID"] = folder is { } folderId ? SwiftId(folderId) : null,
            ["splitGroupID"] = split is { } group ? SwiftId(group) : null,
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0
        };

        private static JsonObject Folder(Guid id, string location, bool collapsed) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Folder",
            ["location"] = location,
            ["isCollapsed"] = collapsed
        };
    }
}
