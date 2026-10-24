using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Only the request still pending unlocks a Space, for its exact profile;
/// locking cancels it and revokes grants, except while the system's own
/// prompt made the scene inactive; a borrowed workspace follows its source.
public sealed partial class BrowserContractsTests {
    /// A session whose two Spaces both ask for authentication, and a device
    /// showing it.
    private static (NativeSessionAuthority Core, TestDevice Device, Guid First, Guid Second) GuardedDevice() {
        var session = GuardedSession(withOpenSecondSpace: true);
        session["spaces"]![1]!["accessPolicy"] = "deviceOwnerAuthentication";
        var device = new TestDevice(session);
        return (device.Authority, device, SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
    }

    private static SpaceLockChanged Access(IReadOnlyList<Change> changes) => Assert.Single(changes.OfType<SpaceLockChanged>());

    [Fact]
    public void OnlyThePendingRequestUnlocksItsSpacesProfileAndNeverTwice() {
        var (core, device, first, _) = GuardedDevice();
        using var disposal = device;
        var profile = core.Current.Spaces[0].ProfileId;
        var request = Guid.NewGuid();

        Assert.Equal(new SpaceLockChanged(first, profile, IsUnlocked: false, IsAuthenticating: true),
            Access(device.Send(new BeginUnlockingSpace(device.Workspace, first, request))));
        var stranger = Guid.NewGuid();
        Assert.Equal(new StaleUnlockRequest(stranger), Assert.Throws<Rejected>(() =>
            device.Send(new FinishUnlockingSpace(first, stranger, Authenticated: true))).Rejection);
        Assert.Equal(new SpaceLockChanged(first, profile, IsUnlocked: true, IsAuthenticating: false),
            Access(device.Send(new FinishUnlockingSpace(first, request, Authenticated: true))));
        Assert.Equal(new StaleUnlockRequest(request), Assert.Throws<Rejected>(() =>
            device.Send(new FinishUnlockingSpace(first, request, Authenticated: true))).Rejection);

        // An unlocked Space needs no request, and its records take edits.
        Assert.Empty(device.Send(new BeginUnlockingSpace(device.Workspace, first, Guid.NewGuid())).OfType<SpaceLockChanged>());
        device.Send(new RenameFolder(device.Workspace, first, core.Current.Spaces[0].Folders[0].Id, "Readable"));
    }

    [Fact]
    public void LockingCancelsThePendingRequestSoALateAnswerUnlocksNothing() {
        var (core, device, first, _) = GuardedDevice();
        using var disposal = device;
        var profile = core.Current.Spaces[0].ProfileId;
        var late = Guid.NewGuid();
        device.Send(new BeginUnlockingSpace(device.Workspace, first, late));

        Assert.Equal(new SpaceLockChanged(first, profile, IsUnlocked: false, IsAuthenticating: false),
            Access(device.Send(new LockSpace(first))));
        var current = Guid.NewGuid();
        device.Send(new BeginUnlockingSpace(device.Workspace, first, current));
        Assert.IsType<StaleUnlockRequest>(Assert.Throws<Rejected>(() =>
            device.Send(new FinishUnlockingSpace(first, late, Authenticated: true))).Rejection);
        Assert.True(Access(device.Send(new FinishUnlockingSpace(first, current, Authenticated: true))).IsUnlocked);

        // Explicit locking always revokes.
        Assert.False(Access(device.Send(new LockSpace(first))).IsUnlocked);
        Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() =>
            device.Send(new RenameFolder(device.Workspace, first, core.Current.Spaces[0].Folders[0].Id, "Leaked"))).Rejection);
    }

    [Fact]
    public void AnInactiveSceneKeepsTheWaitingRequestButLockingEverythingRevokesEveryGrant() {
        var (_, device, first, second) = GuardedDevice();
        using var disposal = device;
        Unlock(device.Send, device.Workspace, first);
        var waiting = Guid.NewGuid();
        device.Send(new BeginUnlockingSpace(device.Workspace, second, waiting));

        // The system's own prompt made the scene inactive: nothing locks.
        Assert.Empty(device.Send(new LockAllSpaces(SceneWentInactive: true)).OfType<SpaceLockChanged>());
        var locked = device.Send(new LockAllSpaces(SceneWentInactive: false)).OfType<SpaceLockChanged>().ToList();
        Assert.Equal(new[] { first, second }.Order(), locked.Select(change => change.SpaceId).Order());
        Assert.All(locked, change => Assert.False(change.IsUnlocked || change.IsAuthenticating));
        Assert.IsType<StaleUnlockRequest>(Assert.Throws<Rejected>(() =>
            device.Send(new FinishUnlockingSpace(second, waiting, Authenticated: true))).Rejection);
        // With no request waiting, an inactive scene locks as well.
        Unlock(device.Send, device.Workspace, first);
        Assert.False(Access(device.Send(new LockAllSpaces(SceneWentInactive: true))).IsUnlocked);
    }

    [Fact]
    public void OneRequestWaitsAtATimeAndADenialEndsItWithoutAGrant() {
        var (_, device, first, second) = GuardedDevice();
        using var disposal = device;
        var request = Guid.NewGuid();
        device.Send(new BeginUnlockingSpace(device.Workspace, first, request));

        Assert.IsType<AuthenticationBusy>(Assert.Throws<Rejected>(() =>
            device.Send(new BeginUnlockingSpace(device.Workspace, first, Guid.NewGuid()))).Rejection);
        Assert.IsType<AuthenticationBusy>(Assert.Throws<Rejected>(() =>
            device.Send(new BeginUnlockingSpace(device.Workspace, second, Guid.NewGuid()))).Rejection);
        var denied = Access(device.Send(new FinishUnlockingSpace(first, request, Authenticated: false)));
        Assert.False(denied.IsUnlocked || denied.IsAuthenticating);
        var missing = Guid.NewGuid();
        Assert.Equal(new UnknownSpace(missing), Assert.Throws<Rejected>(() =>
            device.Send(new BeginUnlockingSpace(device.Workspace, missing, Guid.NewGuid()))).Rejection);
        Unlock(device.Send, device.Workspace, second);
    }

    [Fact]
    public void ABorrowedWorkspaceUnlocksAndLocksWithItsSource() {
        var (core, device, first, _) = GuardedDevice();
        using var disposal = device;
        Unlock(device.Send, device.Workspace, first);
        var borrowed = TestWorkspaces.Opened(device.Send(new BorrowSpace(device.Workspace, first, core.Current.Spaces[0].ProfileId)));
        device.Send(new ClearHistory(borrowed, first));

        device.Send(new LockSpace(first));
        Assert.Equal(new SpaceLocked(first), Assert.Throws<Rejected>(() => device.Send(new ClearHistory(borrowed, first))).Rejection);
        // Unlocking through the borrowed workspace unlocks the Space its source holds.
        Unlock(device.Send, borrowed, first);
        device.Send(new ClearHistory(device.Workspace, first));
    }
}
