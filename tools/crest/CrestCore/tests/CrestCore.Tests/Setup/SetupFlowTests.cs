using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Setup as the core walks a person through it: where each entry opens and
/// where Back and Next lead on each platform, the queue of browsers it imports
/// in turn, finishing, which applies the manual setup and opens the Getting
/// Started guide only in an unlocked first Space, and whether the device has
/// completed setup, which the device store adopts once and keeps.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void CompletionIsAdoptedOnceAndKeptInTheDeviceStore() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        Guid first = SpaceId(document["spaces"]![0]!);
        using (var app = new CrestApp(configuration)) {
            app.Send(Adoption(document));
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            Assert.Contains(new SetupCompletedChanged(false), app.Send(new AdoptSetupCompletion(Completed: false)));
            var fresh = Flowing(app.Send(new StartSetup(workspace, SetupEntry.FirstRun)));
            Assert.Equal((true, false), (fresh.OpensGuide, fresh.OpensCrestFromWelcome));
            var finished = app.Send(new FinishSetup(Guid.NewGuid()));
            Assert.Contains(new SetupCompletedChanged(true), finished);
            Assert.Contains(new SetupFinished(workspace, first), finished);
        }
        using (var app = new CrestApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            // The store adopted once: what an installed release kept no longer counts.
            Assert.Contains(new SetupCompletedChanged(true), app.Send(new AdoptSetupCompletion(Completed: false)));
            var again = Flowing(app.Send(new StartSetup(workspace, SetupEntry.FirstRun)));
            Assert.Equal((false, true), (again.OpensGuide, again.OpensCrestFromWelcome));
            Assert.True(Flowing(app.Send(new StartSetup(workspace, SetupEntry.Rerun))).OpensGuide);
        }
        using var adopting = new StorageDirectory();
        using (var app = new CrestApp(new AppConfiguration(adopting.Path, DevicePlatform.Desktop))) {
            app.Send(Adoption(document));
            Assert.Contains(new SetupCompletedChanged(true), app.Send(new AdoptSetupCompletion(Completed: true)));
        }
        using var reopened = new CrestApp(new AppConfiguration(adopting.Path, DevicePlatform.Desktop));
        Assert.Contains(new SetupCompletedChanged(true), reopened.Send(new AdoptSetupCompletion(Completed: false)));
    }
}
