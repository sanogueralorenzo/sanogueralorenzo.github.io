using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void NewBrowsingPreferencesSweepTheSpaceUnderTheirRetention() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]![0]!["history"] = new JsonArray(new JsonObject {
            ["id"] = Guid.NewGuid().ToString(),
            ["url"] = "https://example.com/old",
            ["title"] = "Old visit",
            ["firstVisitedAt"] = 0.0,
            ["lastVisitedAt"] = 0.0,
            ["visitCount"] = 1
        });
        using var device = new TestDevice(session);
        var core = device.Authority;
        var space = core.Current.Spaces[0];
        var preferences = space.Settings.BrowsingPreferences;
        Assert.Single(space.History);

        device.Send(new SetBrowsingPreferences(device.Workspace, space.Id, preferences.ContentBlocking,
            preferences.DataRetention));
        Assert.Single(core.Current.Spaces[0].History);

        device.Send(new SetBrowsingPreferences(device.Workspace, space.Id, preferences.ContentBlocking,
            preferences.DataRetention with { History = DataRetention.OneDay }));
        var swept = core.Current.Spaces[0];
        Assert.Empty(swept.History);
        Assert.Equal(DataRetention.OneDay, swept.Settings.BrowsingPreferences.DataRetention.History);
    }
}
