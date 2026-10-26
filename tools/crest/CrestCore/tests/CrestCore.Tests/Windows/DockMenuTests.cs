using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The Dock icon's menu: the core lists the persistent session's Spaces in
/// order, checks the one the frontmost window shows, says which are locked
/// and where a chosen Space goes, and a private window never takes one. An
/// engine's own browser window goes to the window the person uses the same
/// way.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void AnEngineWindowJoinsTheFrontWindowOfItsProfilesOnlyShowableSpace() {
        var session = GuardedSession(withOpenSecondSpace: true);
        var (app, _, _, workspace, front) = PageHost(session);
        using var disposal = app;
        var lockedProfile = Identity(session).Profile;
        var (open, profile) = (SpaceId(session["spaces"]![1]!), ProfileId(session["spaces"]![1]!));
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)));
        var privateWindow = Guid.NewGuid();
        app.Send(new OpenWindow(privateWindow, privateWorkspace, Saved: false, null, null, [], RestoresTabs: true));
        var privateSpace = app.Workspace(privateWorkspace).Current.Spaces.Single();
        EngineWindowPlace Place(Guid profileId, bool ownWindow, params Guid[] stacked) =>
            app.Query(new EngineWindowPlacement(profileId, ownWindow, stacked));
        var declined = new EngineWindowPlace(null, null, OpensWindow: false);

        // The Space's tabs join the frontmost window over the person's own
        // Spaces, past a private one; a window of its own, or none open, opens one.
        Assert.Equal(new EngineWindowPlace(front, open, OpensWindow: false), Place(profile, false, privateWindow, front));
        var own = Place(profile, true, front);
        Assert.Equal((open, true), (own.SpaceId, own.OpensWindow));
        Assert.NotEqual(front, own.WindowId);
        Assert.True(Place(profile, false, privateWindow).OpensWindow);
        // A locked Space, or a profile no Space holds, is declined.
        Assert.Equal(declined, Place(lockedProfile, false, front));
        Assert.Equal(declined, Place(Guid.NewGuid(), false, front));
        // A private Space's tabs join the private window while it is stacked.
        Assert.Equal(new EngineWindowPlace(privateWindow, privateSpace.Id, OpensWindow: false),
            Place(privateSpace.ProfileId, true, front, privateWindow));
        Assert.Equal(declined, Place(privateSpace.ProfileId, false, front));
    }
}
