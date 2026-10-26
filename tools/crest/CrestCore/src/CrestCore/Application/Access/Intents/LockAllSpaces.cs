using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Locks every Space again, cancelling a request waiting to unlock one. When
/// `SceneWentInactive`, the scene may only have made way for the system's own
/// authentication prompt, so while a request is waiting nothing locks.
public sealed record LockAllSpaces(bool SceneWentInactive) : SpaceAccessIntent {
    #region Actions - Access

    internal override void Apply(SpaceAccess access, ChangeFeed changes) =>
        access.Changing(changes, authority => authority.LockAll(SceneWentInactive));

    #endregion
}
