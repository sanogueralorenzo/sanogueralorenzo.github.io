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
    public void HistoryRemovalUsesLastVisitsHalfOpenRangeAndAddressesWithoutTheirFragment() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        space["history"] = new JsonArray([.. new[] { 10.0, 20.0, 30.0 }.Select(time => (JsonNode)Visit(time, $"https://example.org/{time}"))]);
        using var device = new TestDevice(session);
        var core = device.Authority;
        DateTimeOffset At(double seconds) => StoredSessionCodec.Date(seconds);

        Assert.IsType<InvalidDateRange>(Assert.Throws<Rejected>(() =>
            device.Send(new RemoveHistoryRange(device.Workspace, f.Space, At(30), At(10)))).Rejection);
        device.Send(new RemoveHistoryRange(device.Workspace, f.Space, At(10), At(30)));
        var retained = Assert.Single(SavedHistory(core, f.Space));
        Assert.Equal(30.0, retained!["lastVisitedAt"]!.GetValue<double>());
        device.Send(new RemoveHistoryAddress(device.Workspace, f.Space, "https://example.org/30#ignored"));
        Assert.Empty(SavedHistory(core, f.Space));

        space["history"] = new JsonArray(Visit(40, "https://example.org/40"));
        using var other = new TestDevice(session);
        var cleared = other.Authority;
        Assert.IsType<UnknownSpace>(Assert.Throws<Rejected>(() => other.Send(new ClearHistory(other.Workspace, Guid.NewGuid()))).Rejection);
        other.Send(new ClearHistory(other.Workspace, f.Space));
        Assert.Empty(SavedHistory(cleared, f.Space));
    }

    [Fact]
    public void RestoringAnArchivedTabReopensItByIdentityAndShowsItOnce() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!.DeepClone(); var id = Guid.NewGuid(); tab["id"] = SwiftId(id);
        space["archivedTabs"] = new JsonArray(new JsonObject { ["tab"] = tab, ["archivedAt"] = 0.0, ["reason"] = "closed" });
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Showing(session);

        device.Send(new RestoreArchivedTab(device.Workspace, window, f.Space, id));

        var saved = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!;
        var restored = saved["tabs"]!.AsArray().Single(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>()) == id)!;
        Assert.Equal("current", restored["placement"]!.GetValue<string>());
        Assert.Null(restored["folderID"]); Assert.Null(restored["splitGroupID"]);
        Assert.True(JsonNode.DeepEquals(tab["iconAccent"], restored["iconAccent"]));
        Assert.Empty(saved["archivedTabs"]!.AsArray());
        Assert.Equal(id, device.Tab(window, f.Space));
        Assert.Equal(id, Assert.IsType<UnknownArchivedTab>(Assert.Throws<Rejected>(() =>
            device.Send(new RestoreArchivedTab(device.Workspace, window, f.Space, id))).Rejection).TabId);
    }

    [Fact]
    public void ArchiveRetentionRemovesOnlyTheExpiredOccurrenceOfALegacyRepeatedIdentity() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!.DeepClone(); tab["id"] = SwiftId(Guid.NewGuid());
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["archive"] = "oneDay" };
        space["archivedTabs"] = new JsonArray(
            new JsonObject { ["tab"] = tab.DeepClone(), ["archivedAt"] = 0.0, ["reason"] = "closed" },
            new JsonObject { ["tab"] = tab.DeepClone(), ["archivedAt"] = 900000.0, ["reason"] = "closed" });
        using var device = new TestDevice(session);
        var core = device.Authority;
        device.Clock.Now = StoredSessionCodec.Date(900001.0);

        device.Send(new SweepExpiredRecords(device.Workspace));

        var saved = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!["archivedTabs"]!;
        Assert.Equal(900000.0, Assert.Single(saved.AsArray())!["archivedAt"]!.GetValue<double>());
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

    [Fact]
    public void ASweepWithinAMinuteOfTheLastDoesNothingUnlessRetentionChanged() {
        const double start = 800000000, day = 86400;
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneWeek" };
        // One visit turns a week old half a minute after the first sweep; the other is two days old.
        space["history"] = new JsonArray(Visit(start - 7 * day + 30, "https://example.org/expiring"),
            Visit(start - 2 * day, "https://example.org/recent"));
        using var device = new TestDevice(session);
        var core = device.Authority;
        void SweepAt(double seconds) {
            device.Clock.Now = StoredSessionCodec.Date(seconds);
            device.Send(new SweepExpiredRecords(device.Workspace));
        }
        SweepAt(start);
        Assert.Equal(2, SavedHistory(core, f.Space).Count);

        SweepAt(start + 59);
        Assert.Equal(2, SavedHistory(core, f.Space).Count);
        SweepAt(start + 60);
        Assert.Single(SavedHistory(core, f.Space));

        // Shortening retention sweeps under it straight away.
        var preferences = core.Current.Spaces[0].Settings.BrowsingPreferences;
        device.Send(new SetBrowsingPreferences(device.Workspace, f.Space, preferences.CurrentTabCleanup, preferences.ContentBlocking,
            preferences.DataRetention with { History = DataRetention.OneDay }));
        Assert.Empty(SavedHistory(core, f.Space));
    }

    [Fact]
    public void SplitIdentityEditsKeepIndependentFieldClocksAndRejectMissingGroups() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var first = space["tabs"]![0]!; var group = Guid.Parse(first["splitGroupID"]!["rawValue"]!.GetValue<string>());
        var second = first.DeepClone(); second["id"] = SwiftId(Guid.NewGuid()); space["tabs"]!.AsArray().Add(second);
        space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = SwiftId(group), ["customIconSymbol"] = "crest.emoji:🌊", ["iconModifiedAt"] = 123.0 });
        using var device = new TestDevice(session);
        var core = device.Authority;
        device.Send(new NameSplit(device.Workspace, f.Space, group, "  Research  "));
        var metadata = JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!["splitGroups"]![0]!;
        Assert.Equal("Research", metadata["customTitle"]!.GetValue<string>());
        Assert.Equal(123.0, metadata["iconModifiedAt"]!.GetValue<double>());
        Assert.Equal("crest.emoji:🌊", metadata["customIconSymbol"]!.GetValue<string>());
        var missing = Guid.NewGuid();
        Assert.Equal(missing, Assert.IsType<UnknownSplitGroup>(Assert.Throws<Rejected>(() =>
            device.Send(new NameSplit(device.Workspace, f.Space, missing, "Invalid"))).Rejection).GroupId);
    }

}
