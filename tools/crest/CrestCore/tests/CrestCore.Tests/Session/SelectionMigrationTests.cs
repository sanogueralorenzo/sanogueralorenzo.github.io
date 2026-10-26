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

}
