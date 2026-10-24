using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A tab's icon, the page it is showing and the page it belongs to are decided
/// once, here, and published with the tab, so no platform works them out
/// again. The image bytes stay in the native cache; these edits only name the
/// tab whose stored image the platform must replace or drop.
public sealed partial class BrowserContractsTests {
    private static TabState WebTab(string url, TabPlacement placement, string? savedUrl = null, string symbol = TabIconMode.WebSymbol,
        TabIconMode? mode = null, string? favicon = null, string? rename = null) => new(Guid.NewGuid(), "Page title", url, null, savedUrl,
        symbol, favicon, null, mode, placement, null, null, DateTimeOffset.UnixEpoch, null, rename, null, false);

    [Fact]
    public void ATabsIconIsFilledTheWayItChoseOrForAnOlderTabTheWayItsSymbolSays() {
        foreach (var mode in TabIconMode.All)
            Assert.Same(mode, WebTab("https://example.com/", TabPlacement.Current, symbol: "crest.emoji:🌊", mode: mode).IconMode);
        // A tab written before modes were stored, or with a term this build
        // cannot name, has none: an emoji symbol means an emoji, and any other
        // symbol follows the page. A pulled favicon is never inferred.
        Assert.Same(TabIconMode.Emoji, WebTab("https://example.com/", TabPlacement.Current, symbol: "crest.emoji:🌊").IconMode);
        Assert.Same(TabIconMode.Automatic, WebTab("https://example.com/", TabPlacement.Current).IconMode);
        Assert.Same(TabIconMode.Automatic, WebTab("https://example.com/", TabPlacement.Current, symbol: "crest.emoji:").IconMode);
        Assert.Same(TabIconMode.Automatic, WebTab("https://example.com/", TabPlacement.Current, symbol: "book").IconMode);
    }

    [Fact]
    public void ATabPublishesItsNameWhetherItIsAwayAndWhetherItsPageIconIsCurrent() {
        Assert.Equal("Mine", WebTab("https://example.com/", TabPlacement.Current, rename: "  Mine ").DisplayTitle);
        Assert.Equal("Page title", WebTab("https://example.com/", TabPlacement.Current, rename: " \n").DisplayTitle);

        // Only a saved or pinned tab belongs to an address, and a fragment
        // points within the page it names.
        Assert.True(WebTab("https://example.com/article", TabPlacement.Saved, "https://example.com/").IsAwayFromSavedAddress);
        Assert.False(WebTab("https://example.com/#top", TabPlacement.Pinned, "https://example.com/").IsAwayFromSavedAddress);
        Assert.False(WebTab("https://example.com/article", TabPlacement.Pinned).IsAwayFromSavedAddress);
        Assert.False(WebTab("https://example.com/article", TabPlacement.Current, "https://example.com/").IsAwayFromSavedAddress);

        // A favicon kept for this page stays current while the icon follows it.
        Assert.True(WebTab("https://example.com/#top", TabPlacement.Current, favicon: "https://example.com/").PageIconIsCurrent);
        Assert.False(WebTab("https://example.com/next", TabPlacement.Current, favicon: "https://example.com/").PageIconIsCurrent);
        Assert.False(WebTab("https://example.com/", TabPlacement.Current, mode: TabIconMode.Pulled,
            favicon: "https://example.com/").PageIconIsCurrent);
        Assert.False(WebTab("https://example.com/", TabPlacement.Current).PageIconIsCurrent);
    }

    [Fact]
    public void ASavedTabReplacesOrReturnsToTheAddressItBelongsToAndAnOpenTabBelongsNowhere() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        using var device = new TestDevice(session);
        var core = device.Authority;
        TabState Tab() => core.Current.Spaces[0].Tabs[0];
        Assert.True(Tab().IsAwayFromSavedAddress);

        device.Send(new ReplaceSavedAddress(device.Workspace, fixture.Space, fixture.Tab));
        Assert.Equal(("https://example.com/article#one", false), (Tab().SavedUrl, Tab().IsAwayFromSavedAddress));
        // Already home, so returning changes nothing.
        var home = core.Current;
        device.Send(new ReturnToSavedAddress(device.Workspace, fixture.Space, fixture.Tab));
        Assert.Same(home, core.Current);

        using var elsewhere = new TestDevice(session);
        var away = elsewhere.Authority;
        elsewhere.Send(new ReturnToSavedAddress(elsewhere.Workspace, fixture.Space, fixture.Tab));
        Assert.Equal(("https://example.com/", "https://example.com/", false), (away.Current.Spaces[0].Tabs[0].Url,
            away.Current.Spaces[0].Tabs[0].SavedUrl, away.Current.Spaces[0].Tabs[0].IsAwayFromSavedAddress));

        // An open tab is wherever browsing took it; it belongs nowhere.
        var open = session.DeepClone();
        var tab = open["spaces"]![0]!["tabs"]![0]!;
        tab["placement"] = "current"; tab["savedURL"] = null; tab["folderID"] = null;
        using var browsing = new TestDevice(open);
        var current = browsing.Authority;
        var before = current.Current;
        Assert.Equal(fixture.Tab, Assert.IsType<NoSavedAddress>(Assert.Throws<Rejected>(() =>
            browsing.Send(new ReplaceSavedAddress(browsing.Workspace, fixture.Space, fixture.Tab))).Rejection).TabId);
        Assert.IsType<NoSavedAddress>(Assert.Throws<Rejected>(() =>
            browsing.Send(new ReturnToSavedAddress(browsing.Workspace, fixture.Space, fixture.Tab))).Rejection);
        Assert.Same(before, current.Current);
    }

    [Fact]
    public void ChoosingATabsIconNamesTheImageItWearsEvenWhenNothingElseChanges() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        using var device = new TestDevice(session);
        var core = device.Authority;
        TabState Tab() => core.Current.Spaces[0].Tabs[0];
        ChooseTabIcon Choosing(TabIconMode mode, string? emoji = null, TabIconAccent? accent = null) =>
            new(device.Workspace, fixture.Space, fixture.Tab, mode, emoji, accent);

        Assert.Same(TabIconMode.Emoji, Assert.IsType<InvalidTabIcon>(Assert.Throws<Rejected>(() =>
            device.Send(Choosing(TabIconMode.Emoji, " "))).Rejection).Mode);
        Assert.IsType<InvalidTabIcon>(Assert.Throws<Rejected>(() => device.Send(Choosing(TabIconMode.Emoji, "abc"))).Rejection);

        // A pulled favicon keeps the page's address and color and wears the
        // image its chooser holds, again when it is pulled again.
        var accent = new TabIconAccent(0.1, 0.2, 0.3);
        for (int pull = 0; pull < 2; pull++) {
            var pulled = device.Send(Choosing(TabIconMode.Pulled, accent: accent));
            Assert.Contains(new TabFaviconAssigned(device.Workspace, fixture.Tab, Adopts: true, null), pulled);
            Assert.Equal((TabIconMode.Pulled, TabIconMode.WebSymbol, "https://example.com/article#one", accent),
                (Tab().IconMode, Tab().Symbol, Tab().FaviconUrl, Tab().IconAccent));
        }

        // Any other choice drops the image the tab wore. An emoji keeps the
        // one character that presents as an emoji, modifiers and all.
        var chosen = device.Send(Choosing(TabIconMode.Emoji, " 📚 and more"));
        Assert.Contains(new TabFaviconAssigned(device.Workspace, fixture.Tab, Adopts: false, null), chosen);
        Assert.Equal((TabIconMode.Emoji, "crest.emoji:📚", (string?)null, (TabIconAccent?)null),
            (Tab().StoredIconMode, Tab().Symbol, Tab().FaviconUrl, Tab().IconAccent));
    }

    [Fact]
    public void CreatingAFolderAroundTabsFilesThemInTheSameEdit() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        space["tabs"]![0]!["folderID"] = null;
        space["tabs"]![0]!["splitGroupID"] = null;
        using var device = new TestDevice(session);
        var core = device.Authority;
        var folder = Guid.NewGuid();

        var changes = device.Send(new CreateFolder(device.Workspace, fixture.Space, folder, TabPlacement.Saved, null, null, null, null,
            [fixture.Tab], LeavesSplits: false));

        var edited = core.Current.Spaces[0];
        Assert.Equal("New Folder", edited.Folders.Single(candidate => candidate.Id == folder).Title);
        Assert.Equal(folder, edited.Tabs.Single(tab => tab.Id == fixture.Tab).FolderId);
        // One edit, so no reader ever sees the folder empty.
        Assert.Single(changes.OfType<FoldersChanged>());
        Assert.Single(changes.OfType<TabsChanged>());
    }

}
