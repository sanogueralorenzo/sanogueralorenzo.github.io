using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Selection is window state. Stored documents from earlier releases still carry
/// a session-level `selectedSpaceID` and per-Space `selectedTabID`; they must
/// load and never be written. Native storage folds them into windows once.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ALegacySelectionLoadsButNeverReachesACheckpointOrSurvivesAnEdit() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        Assert.NotNull(session["selectedSpaceID"]); Assert.NotNull(session["spaces"]![0]!["selectedTabID"]);
        var authority = TestWorkspaces.Session(session);

        var saved = JsonNode.Parse(authority.Checkpoint().Read("core"))!;
        Assert.Null(saved["selectedSpaceID"]);
        Assert.Null(saved["spaces"]![0]!["selectedTabID"]);

        // A window showing a tab only records when it was last used; the
        // document still carries no selection.
        using var device = new TestDevice(session);
        device.Send(new ShowTab(device.Open(fixture.Space), fixture.Space, fixture.Tab));
        var touched = JsonNode.Parse(device.Authority.Checkpoint().Read("core"))!["spaces"]![0]!;
        Assert.True(touched["tabs"]![0]!["lastActivatedAt"]!.GetValue<double>() > 800000000.25);
        Assert.Null(touched["selectedTabID"]);
    }

    [Fact]
    public void ClosingTheShownTabReturnsToTheWindowsPreviousTabWhileOtherWindowsKeepTheirOwn() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        JsonNode Current(Guid id) {
            var tab = space["tabs"]![0]!.DeepClone();
            tab["id"] = SwiftId(id); tab["placement"] = "current"; tab["folderID"] = null;
            tab["savedURL"] = null; tab["splitGroupID"] = null;
            return tab;
        }
        Guid earlier = Guid.NewGuid(), closing = Guid.NewGuid();
        space["tabs"]!.AsArray().Add(Current(earlier));
        space["tabs"]!.AsArray().Add(Current(closing));
        using var device = new TestDevice(session);
        var authority = device.Authority;
        var closer = device.Open(fixture.Space);
        foreach (var tab in new[] { fixture.Tab, earlier, closing }) device.Send(new ShowTab(closer, fixture.Space, tab));
        var other = device.Open(fixture.Space);
        device.Send(new ShowTab(other, fixture.Space, fixture.Tab));
        device.Send(new CloseTab(device.Workspace, closer, fixture.Space, closing));
        Assert.Equal(earlier, device.Tab(closer, fixture.Space));
        Assert.Equal(fixture.Space, device.Space(closer));
        // A window showing another tab changes nothing.
        Assert.Equal(fixture.Tab, device.Tab(other, fixture.Space));

        // A tab another window closes leaves this one showing nothing there.
        device.Send(new CloseTab(device.Workspace, other, fixture.Space, earlier));
        Assert.Null(device.Tab(closer, fixture.Space));
    }

    [Fact]
    public void LaunchCleanupKeepsEveryTabARestoredWindowShows() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        space["browsingPreferences"]!["currentTabCleanupPolicy"] = "after12Hours";
        Guid Stale() {
            var tab = space["tabs"]![0]!.DeepClone(); var id = Guid.NewGuid();
            tab["id"] = SwiftId(id); tab["placement"] = "current"; tab["folderID"] = null; tab["savedURL"] = null;
            tab["splitGroupID"] = null; tab["lastActivatedAt"] = 0.0;
            space["tabs"]!.AsArray().Add(tab);
            return id;
        }
        Guid shownElsewhere = Stale(), unshown = Stale();
        using var device = new TestDevice(session);
        var authority = device.Authority;
        device.Open(fixture.Space, (fixture.Space, shownElsewhere));
        device.Clock.Now = StoredSessionCodec.Date(800000100);
        device.Send(new SweepExpiredRecords(device.Workspace));
        var tabs = JsonNode.Parse(authority.Checkpoint().Read("core"))!["spaces"]![0]!["tabs"]!.AsArray()
            .Select(t => Guid.Parse(t!["id"]!["rawValue"]!.GetValue<string>())).ToArray();
        Assert.Contains(shownElsewhere, tabs);
        Assert.DoesNotContain(unshown, tabs);
    }
}
