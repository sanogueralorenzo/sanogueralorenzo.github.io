using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The manual setup the device holds: how it starts, grows and follows the
/// workspace while it waits, where it waits for the next launch, and the
/// unfinished setup an installed release kept, which the device store adopts.
public sealed partial class BrowserContractsTests {
    /// The setup the last `SetupDraftChanged` among `changes` published.
    private static SetupDraft Drafted(IReadOnlyList<Change> changes) =>
        Assert.IsType<SetupDraftChanged>(changes.Last(change => change is SetupDraftChanged)).Draft!;

    [Fact]
    public void AManualSetupGrowsWithinTheLimitAndFollowsTheWorkspaceWhileItWaits() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var existing = device.Authority.Current.Spaces[0];

        var started = Drafted(device.Send(new StartSetup(device.Workspace, SetupEntry.ManualSetup)));
        Assert.Equal([(existing.Id, existing.ProfileId, false, "Reading")],
            started.Spaces.Select(space => (space.SpaceId, space.ProfileId, space.IsNew, space.ShownName)));
        // A new Space is named for its place and wears the next accent.
        var added = Drafted(device.Send(new AddSetupSpace())).Spaces[1];
        Assert.Equal((true, "Space 2", SetupDraft.NewSpaceSymbol, SpaceAccent.Orange),
            (added.IsNew, added.ShownName, added.Customization.Symbol, added.Customization.Accent));
        // A blank name stays blank while it is typed and shows as untitled.
        var blank = Drafted(device.Send(new CustomizeSetupSpace(added.SpaceId, added.Customization with { Name = "  " }))).Spaces[1];
        Assert.Equal(("  ", SpaceCustomization.UntitledName), (blank.Customization.Name, blank.ShownName));
        // An existing Space never leaves a setup; a Space created elsewhere joins it.
        Assert.Empty(device.Send(new RemoveSetupSpace(existing.Id)).OfType<SetupDraftChanged>());
        var created = Guid.NewGuid();
        var followed = Drafted(device.Send(new CreateSpace(device.Workspace, window, created)));
        Assert.Equal([existing.Id, added.SpaceId, created], followed.Spaces.Select(space => space.SpaceId));
        // Showing the step again keeps the setup; opening setup again on a Mac does not.
        Assert.Equal(followed, Drafted(device.Send(new ShowSetupStep(SetupStep.ManualSetup))));
        Assert.Equal([existing.Id, created],
            Drafted(device.Send(new StartSetup(device.Workspace, SetupEntry.ManualSetup))).Spaces.Select(space => space.SpaceId));

        for (int count = 2; count < SessionState.MaximumSpaces; count++) device.Send(new AddSetupSpace());
        Assert.Equal(new SpaceLimitReached(SessionState.MaximumSpaces),
            Assert.Throws<Rejected>(() => device.Send(new AddSetupSpace())).Rejection);

        // Setup opened again from the start ends the manual setup.
        Assert.Contains(new SetupDraftChanged(null), device.Send(new StartSetup(device.Workspace, SetupEntry.Rerun)));
        Assert.IsType<NoManualSetup>(Assert.Throws<Rejected>(() => device.Send(new AddSetupSpace())).Rejection);
        var borrowed = device.Attach(session, WorkspaceKind.Private);
        Assert.IsType<PersistentWorkspaceRequired>(
            Assert.Throws<Rejected>(() => device.Send(new StartSetup(borrowed, SetupEntry.ManualSetup))).Rejection);
    }

    [Theory]
    [InlineData("mobile", true)]
    [InlineData("desktop", false)]
    public void AnUnfinishedSetupWaitsForTheNextLaunchOnlyWhereThePlatformKeepsIt(string platform, bool resumes) {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Named(platform)!);
        Guid created;
        using (var app = new CrestApp(configuration)) {
            app.Send(Adoption(document));
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            app.Send(new StartSetup(workspace, SetupEntry.ManualSetup));
            var added = Drafted(app.Send(new AddSetupSpace())).Spaces[^1];
            created = added.SpaceId;
            app.Send(new CustomizeSetupSpace(created, added.Customization with { Name = "Kept" }));
        }
        using (var app = new CrestApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            var resumed = Drafted(app.Send(new StartSetup(workspace, SetupEntry.ManualSetup)));
            Assert.Equal(resumes, resumed.Spaces.Any(space => space.SpaceId == created && space.ShownName == "Kept"));
            app.Send(new StartSetup(workspace, SetupEntry.Rerun));
            Assert.DoesNotContain(Drafted(app.Send(new ShowSetupStep(SetupStep.ManualSetup))).Spaces, space => space.IsNew);
        }
        // Starting over is what the next launch finds.
        using (var app = new CrestApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            Assert.DoesNotContain(Drafted(app.Send(new StartSetup(workspace, SetupEntry.ManualSetup))).Spaces, space => space.IsNew);
        }
    }

    [Fact]
    public void TheSetupAnInstalledReleaseKeptIsAdoptedOnceAndResumes() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        var stored = document["spaces"]![0]!;
        Guid existing = SpaceId(stored), created = Guid.NewGuid();
        JsonObject Legacy(Guid id, JsonNode profile, bool isNew, string name) => new() {
            ["id"] = SwiftId(id),
            ["profile"] = new JsonObject { ["id"] = profile.DeepClone() },
            ["isNew"] = isNew,
            ["existingPinnedTabCount"] = 0,
            ["customization"] = new JsonObject {
                ["name"] = name,
                ["symbol"] = "airplane",
                ["accent"] = "teal",
                ["branding"] = JsonNode.Parse(SavedBranding)
            },
            ["addedTabs"] = new JsonArray()
        };
        byte[] Saved(params JsonObject[] spaces) => Encoding.UTF8.GetBytes(new JsonObject {
            ["spaces"] = new JsonArray([.. spaces]),
            ["spaceOrderWasEdited"] = true
        }.ToJsonString());
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Mobile);
        using (var app = new CrestApp(configuration)) {
            app.Send(Adoption(document));
            TestWorkspaces.OpenStored(app);
            app.Send(new AdoptSetupDraft(Saved(Legacy(created, Guid.NewGuid().ToString(), true, "Trips"),
                Legacy(existing, stored["profile"]!["id"]!, false, "Reading room"))));
            // Adopted once: a later launch's document changes nothing.
            app.Send(new AdoptSetupDraft(Saved(Legacy(Guid.NewGuid(), Guid.NewGuid().ToString(), true, "Later"))));
        }
        using (var app = new CrestApp(configuration)) {
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            var resumed = Drafted(app.Send(new StartSetup(workspace, SetupEntry.ManualSetup)));
            Assert.Equal([(created, true, "Trips"), (existing, false, "Reading room")],
                resumed.Spaces.Select(space => (space.SpaceId, space.IsNew, space.ShownName)));
            Assert.True(resumed.OrderWasEdited);
            Assert.Equal(SpaceAccent.Teal, resumed.Spaces[0].Customization.Accent);
        }
    }
}
