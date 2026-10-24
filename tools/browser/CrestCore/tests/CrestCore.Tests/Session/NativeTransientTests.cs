using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A Quick Window's or Peek's page becomes a tab or an archived tab once, at
/// the address and title the page shows, and a tab takes the live page only
/// where the page already lives.
public sealed partial class BrowserContractsTests {
    /// A Quick Window's page in `space`, hosted by `window`, showing `address`
    /// titled `title`.
    private static Guid TransientPage(TestDevice device, Guid space, Guid window, string address, string title = "") =>
        device.ShowPage(window, space, null, PageSnapshot.Blank with { Url = address, Title = title });

    [Fact]
    public void APromotedPageBecomesATabOnceAndTheTabTakesThePageOnlyInItsOwnSpace() {
        var session = TwoSpaceSession();
        using var device = new TestDevice(session);
        var core = device.Authority;
        device.Register(EngineCapability.WorkspaceTransfer);
        Guid first = SpaceId(session["spaces"]![0]!), second = SpaceId(session["spaces"]![1]!);
        var window = device.Open(first, (first, TabId(session["spaces"]![0]!, 0)));
        var page = TransientPage(device, first, window, "https://quick.example/read", "Quick read");
        var promoting = new PromoteTransientPage(device.Workspace, window, page, first, TabPlacement.Current);

        var promoted = Assert.Single(device.Send(promoting).OfType<TransientPagePromoted>());
        Assert.True(promoted.AdoptsPage);
        var tab = core.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == promoted.TabId);
        Assert.Equal(("Quick read", "https://quick.example/read", TabPlacement.Current), (tab.Title, tab.Url, tab.Placement));
        Assert.Equal(promoted.TabId, device.Tab(window, first));

        Assert.Equal(page, Assert.IsType<TransientAlreadyCompleted>(Assert.Throws<Rejected>(() => device.Send(promoting)).Rejection).PageId);
        Assert.IsType<TransientAlreadyCompleted>(Assert.Throws<Rejected>(() =>
            device.Send(new ArchiveTransientPage(device.Workspace, page, first))).Rejection);

        // Another Space's tab opens a page of its own, and the window follows it there.
        var other = TransientPage(device, first, window, "https://peek.example/");
        Assert.False(Assert.Single(device.Send(new PromoteTransientPage(device.Workspace, window, other, second, TabPlacement.Current))
            .OfType<TransientPagePromoted>()).AdoptsPage);
        Assert.Equal(2, core.Current.Spaces[1].Tabs.Count);
        Assert.Equal(second, device.Space(window));
        var unknown = Guid.NewGuid();
        Assert.Equal(unknown, Assert.IsType<UnknownPage>(Assert.Throws<Rejected>(() => device.Send(
            promoting with { PageId = unknown })).Rejection).PageId);
    }

    [Fact]
    public void AnEngineThatCannotMoveAPageBetweenWindowsLeavesThePromotedTabToOpenItsOwn() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var core = device.Authority;
        device.Register();
        var space = SpaceId(session["spaces"]![0]!);
        var window = device.Open(space);
        var page = TransientPage(device, space, window, "https://quick.example/");

        Assert.False(Assert.Single(device.Send(new PromoteTransientPage(device.Workspace, window, page, space, TabPlacement.Current))
            .OfType<TransientPagePromoted>()).AdoptsPage);
    }

    [Fact]
    public void AnArchivedPageIsKeptOnceInItsSpacesArchiveEvenAfterItsPageIsGone() {
        var session = TwoSpaceSession();
        using var device = new TestDevice(session);
        var core = device.Authority;
        device.Register();
        Guid first = SpaceId(session["spaces"]![0]!), second = SpaceId(session["spaces"]![1]!);
        var window = device.Open(first, (first, TabId(session["spaces"]![0]!, 0)));
        var shown = device.Shown(window);
        var page = TransientPage(device, first, window, "https://idle.example/", "Idle");
        ArchiveTransientPage Archiving(Guid pageId, Guid space) => new(device.Workspace, pageId, space);

        var mismatch = Assert.IsType<PageProfileMismatch>(Assert.Throws<Rejected>(() => device.Send(Archiving(page, second))).Rejection);
        Assert.Equal((page, second), (mismatch.PageId, mismatch.SpaceId));
        device.Send(Archiving(page, first));
        var archived = core.Current.Spaces[0].ArchivedTabs[^1];
        Assert.Equal((ArchiveReason.QuickWindow, "Idle", "https://idle.example/", TabPlacement.Current),
            (archived.Reason, archived.Tab.Title, archived.Tab.Url, archived.Tab.Placement));
        Assert.Equal((shown.ShownSpaceId, shown.ShownTabs), (device.Shown(window).ShownSpaceId, device.Shown(window).ShownTabs),
            new ShownComparer());
        Assert.IsType<TransientAlreadyCompleted>(Assert.Throws<Rejected>(() => device.Send(Archiving(page, first))).Rejection);

        // A page memory pressure took back is archived where it lived, at
        // what it showed last and titled by its host.
        var released = TransientPage(device, first, window, "https://released.example/");
        device.Send(new ReleasePage(released, KeepsState: true));
        device.Send(Archiving(released, first));
        Assert.Equal(("released.example", "https://released.example/"),
            (core.Current.Spaces[0].ArchivedTabs[^1].Tab.Title, core.Current.Spaces[0].ArchivedTabs[^1].Tab.Url));
        var unknown = Guid.NewGuid();
        Assert.Equal(unknown, Assert.IsType<UnknownPage>(Assert.Throws<Rejected>(() => device.Send(Archiving(unknown, first)))
            .Rejection).PageId);
    }

    [Fact]
    public void AnUnloadedQuickWindowPageStaysArchivableUntilItIsArchivedOrLetGoAndAClosedPeekLeavesNothing() {
        var f = SavedSession(); var session = f.Document["session"]!;
        using var device = new TestDevice(session);
        var core = device.Authority;
        device.Register();
        var window = device.Open(f.Space);
        ArchiveTransientPage Archiving(Guid pageId) => new(device.Workspace, pageId, f.Space);
        Guid Refused(Intent intent) =>
            Assert.IsType<UnknownPage>(Assert.Throws<Rejected>(() => device.Send(intent)).Rejection).PageId;

        // However many Peeks come and go, an unloaded Quick Window page keeps
        // what it showed until its window archives it.
        var quick = TransientPage(device, f.Space, window, "https://quick.example/kept", "Kept");
        device.Send(new ReleasePage(quick, KeepsState: true));
        var peeks = Enumerable.Range(0, 40).Select(index => TransientPage(device, f.Space, window, $"https://peek.example/{index}")).ToArray();
        foreach (var peek in peeks) device.Send(new ReleasePage(peek, KeepsState: false));
        device.Send(Archiving(quick));
        Assert.Equal(("Kept", "https://quick.example/kept"),
            (core.Current.Spaces[0].ArchivedTabs[^1].Tab.Title, core.Current.Spaces[0].ArchivedTabs[^1].Tab.Url));
        // The archive forgot it, so its final release finds nothing.
        Assert.Equal(quick, Refused(new ReleasePage(quick, KeepsState: false)));

        // A Peek closed without archiving leaves nothing behind, and a page
        // unloaded then let go for good is forgotten.
        Assert.Equal(peeks[0], Refused(Archiving(peeks[0])));
        var dropped = TransientPage(device, f.Space, window, "https://quick.example/dropped");
        device.Send(new ReleasePage(dropped, KeepsState: true));
        device.Send(new ReleasePage(dropped, KeepsState: false));
        Assert.Equal(dropped, Refused(Archiving(dropped)));
    }
}
