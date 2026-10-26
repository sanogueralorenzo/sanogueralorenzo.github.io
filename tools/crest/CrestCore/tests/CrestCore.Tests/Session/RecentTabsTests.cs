using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A window's recent tabs are the tabs it showed in the Space it shows, the
/// shown one first, a split as one item, and the most recent tab commands
/// follow them rather than the Space's synced last-activated times.
public sealed partial class BrowserContractsTests {
    private static Guid[] RecentFocus(TestDevice device, Guid window) =>
        [.. device.Query(new RecentTabs(window)).Items.Select(item => item.FocusedTabId)];

    private static void ShowAll(TestDevice device, Guid window, Guid space, params Guid[] tabs) {
        foreach (var tab in tabs) device.Send(new ShowTab(window, space, tab));
    }

    /// The list holds five items with the shown one first, leaves a Start Page
    /// out unless it is the shown tab, and the two commands go to its second
    /// and last items.
    [Fact]
    public void RecentTabsHoldFiveItemsAndLeaveOutStartPagesUnlessShown() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        ShowAll(device, window, f.Space, f.C2, f.C3, f.N, f.C5, f.P1, f.P2);
        Assert.Equal([f.P2, f.P1, f.C5, f.C3, f.C2], RecentFocus(device, window));

        device.Send(new ShowMostRecentTab(window));
        Assert.Equal(f.P1, device.Tab(window, f.Space));
        Assert.Equal([f.P1, f.P2, f.C5, f.C3, f.C2], RecentFocus(device, window));
        device.Send(new ShowLeastRecentTab(window));
        Assert.Equal(f.C2, device.Tab(window, f.Space));

        device.Send(new ShowTab(window, f.Space, f.N));
        Assert.Equal([f.N, f.C2, f.P1, f.P2, f.C5], RecentFocus(device, window));
    }

    /// A window that has shown nothing else offers the Space's tab used last,
    /// passing over one another window shows, a split as a whole, and the
    /// command goes there.
    [Fact]
    public void AWindowThatShowedNothingElseOffersTheSpacesTabUsedLast() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var other = device.Open(f.Space, (f.Space, f.C5));
        ShowAll(device, other, f.Space, f.C3, f.C5);
        var window = device.Open(f.Space, (f.Space, f.C1));
        Assert.Equal([f.C1, f.C3], RecentFocus(device, window));

        ShowAll(device, other, f.Space, f.B, f.A);
        Assert.Equal([f.C1, f.C5], RecentFocus(device, window));
        device.Send(new ShowMostRecentTab(window));
        Assert.Equal(f.C5, device.Tab(window, f.Space));
    }

    /// A locked Space lists none of its tabs to switch between, so neither
    /// the panel nor a quick jump reveals or shows them until it unlocks.
    [Fact]
    public void ALockedSpaceListsNoRecentTabsUntilItUnlocks() {
        var session = GuardedSession();
        var identity = Identity(session);
        using var device = new TestDevice(session);
        var window = device.Open(identity.Space);
        var shown = device.Tab(window, identity.Space);

        Assert.Empty(RecentFocus(device, window));
        Assert.Empty(Own(device.Send(new ShowMostRecentTab(window))));
        Assert.Equal(shown, device.Tab(window, identity.Space));

        Unlock(device.Send, device.Workspace, identity.Space);
        Assert.NotEmpty(RecentFocus(device, window));
    }

    /// Each window keeps its own list, whatever the other showed more recently.
    [Fact]
    public void EachWindowKeepsItsOwnRecentTabs() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var first = device.Open(f.Space, (f.Space, f.C1));
        var second = device.Open(f.Space, (f.Space, f.C5));

        ShowAll(device, first, f.Space, f.C2);
        ShowAll(device, second, f.Space, f.C3);
        Assert.Equal([f.C2, f.C1], RecentFocus(device, first));
        Assert.Equal([f.C3, f.C5], RecentFocus(device, second));
        device.Send(new ShowMostRecentTab(second));
        Assert.Equal(f.C5, device.Tab(second, f.Space));
        Assert.Equal(f.C2, device.Tab(first, f.Space));
    }

    /// A split is one item that focuses its page used last: moving between its
    /// pages keeps the order, and the command no longer ping-pongs inside it.
    [Fact]
    public void ASplitIsOneItemAndMovingInsideItKeepsTheOrder() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        ShowAll(device, window, f.Space, f.A, f.C2, f.B);
        var items = device.Query(new RecentTabs(window)).Items;
        Assert.Equal([f.B, f.C2, f.C1], items.Select(item => item.FocusedTabId));
        Assert.Equal([f.A, f.B], items[0].TabIds);

        device.Send(new ShowTab(window, f.Space, f.A));
        Assert.Equal([f.A, f.C2, f.C1], RecentFocus(device, window));

        // From the other tab, the command returns to the page used last, and
        // returning again does not stop inside the split.
        device.Send(new ShowTab(window, f.Space, f.C2));
        device.Send(new ShowMostRecentTab(window));
        Assert.Equal(f.A, device.Tab(window, f.Space));
        device.Send(new ShowTab(window, f.Space, f.B));
        device.Send(new ShowMostRecentTab(window));
        Assert.Equal(f.C2, device.Tab(window, f.Space));
        device.Send(new ShowMostRecentTab(window));
        Assert.Equal(f.B, device.Tab(window, f.Space));
    }

    /// Taking a split apart makes each page its own item.
    [Fact]
    public void ASplitTakenApartBecomesItsPagesAsItems() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        ShowAll(device, window, f.Space, f.A, f.B, f.C2);
        Assert.Equal([f.C2, f.B, f.C1], RecentFocus(device, window));
        device.Send(new SeparateSplits(device.Workspace, window, f.Space, new([f.A, f.B], [], [f.A, f.B])));
        Assert.Equal([f.C2, f.B, f.A, f.C1], RecentFocus(device, window));
    }

    /// A closed tab drops out at once, and switching Space neither counts as
    /// using a tab nor loses the Space's list.
    [Fact]
    public void ClosedTabsDropOutAndSwitchingSpaceKeepsEachSpacesList() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var window = device.Open(f.Space, (f.Space, f.C1));

        ShowAll(device, window, f.Space, f.C2, f.C3);
        device.Send(new CloseTab(device.Workspace, window, f.Space, f.C2));
        Assert.Equal([f.C3, f.C1], RecentFocus(device, window));

        device.Send(new ShowSpace(window, f.Second));
        Assert.Equal([f.SecondTab], RecentFocus(device, window));
        device.Send(new ShowSpace(window, f.Space));
        Assert.Equal([f.C3, f.C1], RecentFocus(device, window));
    }

    /// A tab moved to another window leaves the first window's recent tabs
    /// at once, even while that window still shows it, and returns to them
    /// when the window shows it again; the other window lists it once shown.
    [Fact]
    public void ATabMovedToAnotherWindowLeavesTheFirstWindowsRecentTabs() {
        var f = new OrderSpace();
        using var device = new TestDevice(f.Session);
        var first = device.Open(f.Space, (f.Space, f.C1));
        var second = device.Open(f.Space, (f.Space, f.C5));

        ShowAll(device, first, f.Space, f.C2, f.C3);
        device.Send(new MoveTabToWindow(device.Workspace, first, f.Space, f.C2, second));
        Assert.Equal([f.C3, f.C1], RecentFocus(device, first));
        Assert.Equal([f.C2, f.C5], RecentFocus(device, second));

        // The first window still shows the moved tab it was on, then drops it.
        device.Send(new MoveTabToWindow(device.Workspace, first, f.Space, f.C3, second));
        Assert.Equal([f.C3, f.C1], RecentFocus(device, first));
        device.Send(new ShowTab(first, f.Space, f.C1));
        var afterwards = RecentFocus(device, first);
        Assert.Equal(f.C1, afterwards[0]);
        Assert.DoesNotContain(f.C2, afterwards);
        Assert.DoesNotContain(f.C3, afterwards);
        device.Send(new ShowTab(first, f.Space, f.C3));
        Assert.Equal([f.C3, f.C1], RecentFocus(device, first));
    }
}
