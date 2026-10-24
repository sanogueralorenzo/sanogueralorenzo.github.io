using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Starts unlocking a Space of a workspace as the request `RequestId`, which
/// the platform answers once the device owner has authenticated or declined.
/// One request waits at a time. A Space that opens freely, or that this
/// process already unlocked, needs no request and changes nothing.
public sealed record BeginUnlockingSpace(Guid WorkspaceId, Guid SpaceId, Guid RequestId) : SpaceAccessIntent {
    #region Actions - Access

    /// The Space is read before the grants are locked, so the session's gate
    /// is never taken inside the authority's.
    internal override void Apply(SpaceAccess access, ChangeFeed changes) {
        var unlocking = access.Device.Workspace(WorkspaceId).Unlockable(SpaceId);
        access.Changing(changes, authority => authority.Begin(unlocking.Assignment, unlocking.RequiresAuthentication, RequestId));
    }

    #endregion
}
