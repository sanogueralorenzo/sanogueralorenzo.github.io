using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Locks a Space again: every grant for it is revoked, and a request waiting
/// to unlock it is cancelled.
public sealed record LockSpace(Guid SpaceId) : SpaceAccessIntent {
    #region Actions - Access

    internal override void Apply(SpaceAccess access, ChangeFeed changes) => access.Changing(changes, authority => authority.Lock(SpaceId));

    #endregion
}
