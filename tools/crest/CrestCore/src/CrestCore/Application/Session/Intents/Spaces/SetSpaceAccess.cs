using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets whether a Space opens freely or asks the device owner first, which
/// reaches the person's other devices with the time they chose. Asking for
/// authentication is always allowed; letting a locked Space open freely takes
/// the grant that unlocking it gives.
public sealed record SetSpaceAccess(Guid WorkspaceId, Guid SpaceId, SpaceAccessPolicy Policy) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Asking for authentication is always allowed, even for a locked Space;
    /// letting a Space open freely is the decision authentication guards.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId, maintains: Policy != SpaceAccessPolicy.Open);
        return workspace.SettingSpace(turn.Basis, space, settings => settings with {
            AccessPolicy = Policy,
            AccessPolicyModifiedAt = Policy == settings.AccessPolicy
                ? settings.AccessPolicyModifiedAt : Chosen(settings.AccessPolicyModifiedAt, turn.Now)
        }, SyncStaging.Protection);
    }

    /// When a new choice is made: now, or a second after the choice it
    /// replaces when this device's clock is behind the one that made it, so
    /// the newer choice always wins a merge.
    private static DateTimeOffset Chosen(DateTimeOffset? replaced, DateTimeOffset now) =>
        replaced is { } earlier && earlier >= now ? earlier.AddSeconds(1) : now;

    #endregion
}
