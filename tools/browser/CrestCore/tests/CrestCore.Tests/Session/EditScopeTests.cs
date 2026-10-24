using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// What an accepted edit reads to check the session it leaves: only the
/// Spaces it changed.
public sealed partial class BrowserContractsTests {
    /// A page's navigation and a rename in one Space never read another
    /// Space's tabs, however many it holds.
    [Fact]
    public void AnEditToOneSpaceChecksOnlyThatSpace() {
        var now = StoredSessionCodec.Date(StoredSessionCodec.Seconds(DateTimeOffset.UtcNow));
        var template = SpaceTemplate.For(privateBrowsing: false);
        var browsing = template.Make(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid, number: 1, now);
        browsing = browsing with {
            Tabs = [browsing.Tabs[0] with { Url = "https://example.com/", Title = "Example" }]
        };
        var other = template.Make(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid, number: 2, now);
        other = other with { Tabs = [.. Enumerable.Range(0, 300).Select(_ => other.Tabs[0] with { Id = Guid.NewGuid() })] };
        var session = StoredSessionCodec.Encode(new SessionState([browsing, other], DefaultSpaceId: null, DisposableSeedMarker: null,
            SpaceDeletions: [], AppPreferences: null));
        var (app, engine, page, workspace) = NavigatingPage(session);
        using var disposal = app;
        var identities = app.Workspace(workspace).Identities;

        Browse(app, engine, page, "https://example.com/next", "Next");
        Assert.Equal("https://example.com/next", app.Workspace(workspace).Current.Spaces[0].Tabs[0].Url);
        Assert.Equal([browsing.Id], identities.Last!.Examined);

        app.Send(new RenameTab(workspace, browsing.Id, browsing.Tabs[0].Id, "Renamed"));
        Assert.Equal("Renamed", app.Workspace(workspace).Current.Spaces[0].Tabs[0].CustomTitle);
        Assert.Equal([browsing.Id], identities.Last!.Examined);
    }
}
