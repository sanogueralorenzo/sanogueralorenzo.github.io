using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static TabState FirstTab(NativeSessionAuthority authority) => authority.Current.Spaces[0].Tabs[0];

    [Theory]
    [InlineData("automatic", "globe", true)]
    [InlineData("emoji", "crest.emoji:📚", false)]
    [InlineData("pulled", "globe", false)]
    public void ATabWearsItsDocumentsIconOnlyWhileItsIconFollowsThePage(string mode, string symbol, bool followsPage) {
        var session = SavedSession().Document["session"]!;
        session["spaces"]![0]!["tabs"]![0]!["storedIconMode"] = mode;
        session["spaces"]![0]!["tabs"]![0]!["symbol"] = symbol;
        var (app, workspace, _) = WindowHost(session);
        using var disposal = app;
        var authority = app.Workspace(workspace);
        var tab = FirstTab(authority).Id;
        var space = authority.Current.Spaces[0].Id;
        var page = Guid.NewGuid();
        var accent = new TabIconAccent(0.5, 0.25, 0.125);
        var at = DateTimeOffset.UtcNow;
        var recorded = Own(app.Send(new RecordPageNavigation(workspace, page, space, tab, "https://example.org/", "Example",
            at, Guid.NewGuid(), HasIcon: true, accent)));
        if (!followsPage) {
            Assert.DoesNotContain(recorded, change => change is TabFaviconAssigned);
            Assert.Equal(symbol, FirstTab(authority).Symbol);
            return;
        }
        Assert.Contains(new TabFaviconAssigned(workspace, tab, Adopts: true, page), recorded);
        Assert.Equal(("https://example.org/", accent), (FirstTab(authority).FaviconUrl, FirstTab(authority).IconAccent));
        var themed = new TabIconAccent(1, 0, 0);
        var changed = Own(app.Send(new RecordPageIcon(workspace, page, space, tab, "https://example.org/", themed, at)));
        Assert.Equal([typeof(TabsChanged), typeof(TabFaviconAssigned)], changed.Select(change => change.GetType()));
        Assert.Equal(themed, FirstTab(authority).IconAccent);
        app.Send(new RecordPageNavigation(workspace, page, space, tab, "https://example.net/", "Elsewhere", at, Guid.NewGuid(),
            HasIcon: false, IconAccent: null));
        Assert.Equal("https://example.org/", FirstTab(authority).FaviconUrl);
    }

    [Fact]
    public void NavigatingANativeTabGivesItAWebAddressAndLeavesAWebPageToItsEngine() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var tab = session["spaces"]![0]!["tabs"]![0]!.AsObject();
        tab["url"] = null;
        tab["savedURL"] = null;
        tab["nativeContent"] = new JsonObject { ["kind"] = "settings" };
        using var app = new CrestApp();
        var workspace = TestWorkspaces.Open(app, session);
        var authority = app.Workspace(workspace);
        app.Drain();

        // Blank input, and input no page can load, are refused.
        Assert.Equal(new UnsupportedAddress("  "), Refusal(app, new NavigateTab(workspace, fixture.Space, fixture.Tab, "  ")));
        var endless = new string('a', 4097);
        Assert.Equal(new UnsupportedAddress(endless), Refusal(app, new NavigateTab(workspace, fixture.Space, fixture.Tab, endless)));

        // A resolved address gives the native tab a page.
        Assert.IsType<TabsChanged>(Assert.Single(app.Send(new NavigateTab(workspace, fixture.Space, fixture.Tab, "https://example.org"))));
        Assert.Null(FirstTab(authority).NativeContent);
        Assert.Equal(("https://example.org", "example.org"), (FirstTab(authority).Url, FirstTab(authority).Title));

        // A web page keeps its address until its engine reports one.
        Assert.Empty(app.Send(new NavigateTab(workspace, fixture.Space, fixture.Tab, "https://example.net/")));
        Assert.Equal(new UnknownSpace(fixture.Tab), Refusal(app, new NavigateTab(workspace, fixture.Tab, fixture.Tab, "https://a.example/")));
        var gone = Guid.NewGuid();
        Assert.Equal(new UnknownTab(gone), Refusal(app, new NavigateTab(workspace, fixture.Space, gone, "https://example.net/")));
    }
}
