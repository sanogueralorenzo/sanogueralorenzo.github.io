using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Next and previous tab, the address bar's swipe, and the numbered commands,
/// follow the order a window's sidebar shows: pinned, then saved, then open,
/// top to bottom, a split as one stop, and nothing a Start Page, a collapsed
/// folder or a collapsed saved section hides.
public sealed partial class BrowserContractsTests {
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

    /// The tabs a window shows as it steps from `start`, `count` times.
    private static Guid?[] Stepping(TestDevice device, Guid window, Guid space, AdjacentDirection direction, int count) {
        var shown = new Guid?[count];
        for (int step = 0; step < count; step++) {
            device.Send(new ShowAdjacentTab(window, direction));
            shown[step] = device.Tab(window, space);
        }
        return shown;
    }

    /// Next and previous walk every stop the sidebar shows, in its order, and wrap
    /// at both ends: a split is one stop that shows its first tab, and a Start
    /// Page and the tabs of collapsed folders are no stops.
    [Fact]
    public void NextAndPreviousTabWalkTheSidebarsStopsAndWrap() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.P1));

        Assert.Equal([.. f.Stops.Skip(1), f.P1], Stepping(device, window, f.Space, AdjacentDirection.Next, f.Stops.Length));
        Assert.Equal([.. f.Stops.Reverse()], Stepping(device, window, f.Space, AdjacentDirection.Previous, f.Stops.Length));

        // A split is one stop, whichever of its tabs the window shows.
        device.Send(new ShowTab(window, f.Space, f.B));
        Assert.Equal([f.C2], Stepping(device, window, f.Space, AdjacentDirection.Next, 1));
        device.Send(new ShowTab(window, f.Space, f.B));
        Assert.Equal([f.C1], Stepping(device, window, f.Space, AdjacentDirection.Previous, 1));
    }

    /// A shown tab the sidebar hides in a collapsed folder steps from where it
    /// lives, and a shown Start Page, which the sidebar lists nowhere, from the ends.
    [Theory]
    [InlineData(nameof(OrderSpace.S1), nameof(OrderSpace.S2), nameof(OrderSpace.P2))]
    [InlineData(nameof(OrderSpace.C4), nameof(OrderSpace.C5), nameof(OrderSpace.C3))]
    [InlineData(nameof(OrderSpace.N), nameof(OrderSpace.P1), nameof(OrderSpace.C5))]
    public void AShownTabWithoutAStopStepsFromWhereItLives(string shown, string next, string previous) {
        var f = new OrderSpace();
        Guid Named(string name) => (Guid)typeof(OrderSpace).GetProperty(name)!.GetValue(f)!;
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, Named(shown)));

        Assert.Equal([Named(next)], Stepping(device, window, f.Space, AdjacentDirection.Next, 1));
        device.Send(new ShowTab(window, f.Space, Named(shown)));
        Assert.Equal([Named(previous)], Stepping(device, window, f.Space, AdjacentDirection.Previous, 1));
    }

    /// A collapsed saved section is no stops, and a shown saved tab it hides steps
    /// from where the section sits.
    [Fact]
    public void ACollapsedSavedSectionIsNoStops() {
        var f = new OrderSpace(savedExpanded: false);
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.P2));

        Assert.Equal([f.C1], Stepping(device, window, f.Space, AdjacentDirection.Next, 1));
        device.Send(new ShowTab(window, f.Space, f.S2));
        Assert.Equal([f.C1], Stepping(device, window, f.Space, AdjacentDirection.Next, 1));
        device.Send(new ShowTab(window, f.Space, f.S2));
        Assert.Equal([f.P2], Stepping(device, window, f.Space, AdjacentDirection.Previous, 1));
    }

    /// The tabs a window shows as it swipes `direction` from the tab it shows,
    /// one swipe at a time, until a swipe reaches nothing.
    private static List<Guid> Swiping(TestDevice device, Guid window, Guid space, AdjacentDirection direction) {
        var shown = new List<Guid>();
        while (shown.Count < 32 && device.Query(new SwipeNeighbors(window)) is var neighbors
            && (direction == AdjacentDirection.Next ? neighbors.NextTabId : neighbors.PreviousTabId) is { } tab) {
            device.Send(new ShowTab(window, space, tab));
            shown.Add(tab);
        }
        return shown;
    }

    /// A swipe walks the stops next and previous walk, but card by card through
    /// a split, which it enters at the card nearest the side it comes from. It
    /// stops at both ends rather than wrapping, so it never leaves the Space, and
    /// a tab a collapsed folder hides swipes from where it lives.
    [Fact]
    public void ASwipeWalksTheStopsCardByCardAndStopsAtBothEnds() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.P1));
        Guid[] run = [f.P1, f.P2, f.S2, f.C1, f.A, f.B, f.C2, f.C3, f.C5];

        Assert.Equal(run.Skip(1), Swiping(device, window, f.Space, AdjacentDirection.Next));
        Assert.Equal(new SwipeNeighborTabs(f.C3, NextTabId: null), device.Query(new SwipeNeighbors(window)));
        Assert.Equal(run.Reverse().Skip(1), Swiping(device, window, f.Space, AdjacentDirection.Previous));
        Assert.Equal(new SwipeNeighborTabs(PreviousTabId: null, f.P2), device.Query(new SwipeNeighbors(window)));
        Assert.Equal(f.Space, device.Space(window));

        device.Send(new ShowTab(window, f.Space, f.C4));
        Assert.Equal(new SwipeNeighborTabs(f.C3, f.C5), device.Query(new SwipeNeighbors(window)));
    }

    /// A step that leads back to the stop the window shows, or starts from no
    /// shown tab, publishes nothing.
    [Fact]
    public void AStepWithNowhereElseToGoPublishesNothing() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Second, (f.Second, f.SecondTab));

        Assert.Empty(Own(device.Send(new ShowAdjacentTab(window, AdjacentDirection.Next))));
        device.Send(new ShowTab(window, f.Second, null));
        Assert.Empty(Own(device.Send(new ShowAdjacentTab(window, AdjacentDirection.Previous))));
        Assert.Null(device.Tab(window, f.Second));
    }

    /// ⌘1 through ⌘9 lead to the stops in the same order, a split to its first
    /// tab, and ⌃1 through ⌃9 to the Spaces the window may show, leaving out one
    /// being deleted; a number with nothing at it leads nowhere.
    [Fact]
    public void NumberedCommandsLeadToTheSidebarsStopsAndTheShowableSpaces() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        var selections = device.Query(new NumberedSelections(window)).Selections;
        var tabs = selections.Where(selection => selection.Target == NumberedSelectionTarget.Tab).ToList();
        Assert.Equal(ShortcutCommand.All.Where(command => command.Selects == NumberedSelectionTarget.Tab).Take(f.Stops.Length),
            tabs.Select(selection => selection.Command));
        Assert.Equal(f.Stops.Cast<Guid?>(), tabs.Select(selection => selection.TabId));
        Assert.All(tabs, selection => Assert.Equal(f.Space, selection.SpaceId));
        var spaces = selections.Where(selection => selection.Target == NumberedSelectionTarget.Space).ToList();
        Assert.Equal([f.Space, f.Second, f.Third], spaces.Select(selection => selection.SpaceId));
        Assert.All(spaces, selection => Assert.Null(selection.TabId));

        device.Send(new BeginDeletingSpace(device.Workspace, window, f.Second, Guid.NewGuid()));
        Assert.Equal([f.Space, f.Third], device.Query(new NumberedSelections(window)).Selections
            .Where(selection => selection.Target == NumberedSelectionTarget.Space).Select(selection => selection.SpaceId));
    }

    /// Next and previous Space step through the Spaces the window may show in the
    /// session's order, wrapping, and leave out one being deleted.
    [Fact]
    public void NextAndPreviousSpaceWrapAndSkipASpaceBeingDeleted() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Third, (f.Third, f.ThirdTab));

        device.Send(new ShowAdjacentSpace(window, AdjacentDirection.Next));
        Assert.Equal(f.Space, device.Space(window));
        device.Send(new ShowAdjacentSpace(window, AdjacentDirection.Previous));
        Assert.Equal(f.Third, device.Space(window));

        device.Send(new BeginDeletingSpace(device.Workspace, window, f.Second, Guid.NewGuid()));
        device.Send(new ShowAdjacentSpace(window, AdjacentDirection.Previous));
        Assert.Equal(f.Space, device.Space(window));
        device.Send(new ShowAdjacentSpace(window, AdjacentDirection.Previous));
        Assert.Equal(f.Third, device.Space(window));
    }
}
