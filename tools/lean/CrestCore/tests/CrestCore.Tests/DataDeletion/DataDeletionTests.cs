using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Physical erasure is a native precondition. The session owns operation
/// identity, the committed removal and restartable pending deletions.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASpaceRemovalKeepsItsOperationAcrossRelaunchAndCommitsOnlyThatOperation() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        var second = document["spaces"]![0]!.DeepClone().AsObject();
        second["id"] = SwiftId(Guid.NewGuid()); second["profile"]!["id"] = Guid.NewGuid().ToString();
        second["tabs"] = new JsonArray(); second["folders"] = new JsonArray(); second["history"] = new JsonArray();
        document["spaces"]!.AsArray().Add(second);
        var deleting = SpaceId(second);
        var operation = Guid.NewGuid();
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var answered = app.Send(Adoption(document));
            var (workspace, opened) = TestWorkspaces.OpenStored(app);
            DrainLaunch(app, [.. answered, .. opened]);
            app.Send(new BeginDeletingSpace(workspace, Guid.NewGuid(), deleting, operation));
            Assert.Equal(new WrongDeletionOperation(deleting), Refusal(app,
                new FinishDeletingSpace(workspace, Guid.NewGuid(), deleting, Guid.NewGuid())));
        }
        using var relaunched = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var (again, _) = TestWorkspaces.OpenStored(relaunched);
        Assert.Contains(relaunched.Workspace(again).Current.SpaceDeletions, pending => pending.SpaceId == deleting && pending.Id == operation);
        relaunched.Send(new FinishDeletingSpace(again, Guid.NewGuid(), deleting, operation));
        Assert.DoesNotContain(relaunched.Workspace(again).Current.Spaces, space => space.Id == deleting);
    }
}
