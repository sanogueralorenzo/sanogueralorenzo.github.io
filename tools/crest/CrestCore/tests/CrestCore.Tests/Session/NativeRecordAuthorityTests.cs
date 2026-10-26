using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    /// A history entry last visited at `time`, in the stored date format.
    private static JsonObject Visit(double time, string url) => new() {
        ["id"] = Guid.NewGuid().ToString(),
        ["url"] = url,
        ["title"] = "Visit",
        ["firstVisitedAt"] = 0.0,
        ["lastVisitedAt"] = time,
        ["visitCount"] = 2
    };

    private static JsonArray SavedHistory(NativeSessionAuthority core, Guid space) => JsonNode.Parse(core.Checkpoint().Read(space.ToString()))!.AsArray();

    [Fact]
    public void HistoryRemovalMatchesAddressesWithoutTheirFragmentAndClearingKeepsWhatARangeLeavesOut() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        space["history"] = new JsonArray([.. new[] { 10.0, 30.0 }.Select(time => (JsonNode)Visit(time, $"https://example.org/{time}"))]);
        using var device = new TestDevice(session);
        var core = device.Authority;

        device.Send(new RemoveHistoryAddress(device.Workspace, f.Space, "https://example.org/30#ignored"));
        var retained = Assert.Single(SavedHistory(core, f.Space));
        Assert.Equal(10.0, retained!["lastVisitedAt"]!.GetValue<double>());

        // Clearing a time range removes the addresses visited within it,
        // then all time removes the rest.
        space["history"] = new JsonArray(Visit(800000000, "https://example.org/recent"), Visit(799990000, "https://example.org/older"));
        using var other = new TestDevice(session);
        var cleared = other.Authority;
        other.Clock.Now = StoredSessionCodec.Date(800000100);
        Assert.IsType<UnknownSpace>(Assert.Throws<Rejected>(() =>
            other.Send(new ClearHistory(other.Workspace, Guid.NewGuid(), BrowsingDataRange.AllTime))).Rejection);
        other.Send(new ClearHistory(other.Workspace, f.Space, BrowsingDataRange.LastHour));
        Assert.Equal("https://example.org/older", Assert.Single(SavedHistory(cleared, f.Space))!["url"]!.GetValue<string>());
        other.Send(new ClearHistory(other.Workspace, f.Space, BrowsingDataRange.AllTime));
        Assert.Empty(SavedHistory(cleared, f.Space));
    }

    [Fact]
    public void ASweepArchivesUnusedTabsAndExpiresRecordsButKeepsWhatWindowsShow() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var current = space["tabs"]![0]!.DeepClone(); var currentId = Guid.NewGuid(); current["id"] = SwiftId(currentId);
        current["placement"] = "current"; current["folderID"] = null; current["splitGroupID"] = null; current["lastActivatedAt"] = 0.0;
        space["tabs"]!.AsArray().Add(current);
        space["browsingPreferences"]!["currentTabCleanupPolicy"] = "after12Hours";
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneDay", ["archive"] = "oneDay" };
        space["history"] = new JsonArray(Visit(0, "https://example.com/old"));
        space["archivedTabs"] = new JsonArray();
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Showing(session);
        var shown = device.Shown(window);
        device.Clock.Now = StoredSessionCodec.Date(800000100);

        device.Send(new SweepExpiredRecords(device.Workspace));

        var saved = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!;
        // The tab the window shows survives the sweep, and the window keeps showing it.
        Assert.Single(saved["tabs"]!.AsArray());
        Assert.Equal((shown.ShownSpaceId, shown.ShownTabs), (device.Shown(window).ShownSpaceId, device.Shown(window).ShownTabs),
            new ShownComparer());
        Assert.Equal(currentId, Guid.Parse(Assert.Single(saved["archivedTabs"]!.AsArray())!["tab"]!["id"]!["rawValue"]!.GetValue<string>()));
        Assert.Empty(SavedHistory(core, f.Space));
    }

}
