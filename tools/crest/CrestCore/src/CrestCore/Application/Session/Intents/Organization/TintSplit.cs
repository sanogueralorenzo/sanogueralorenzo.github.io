using CrestCore.Application;

namespace CrestCore.Contracts;

/// Tints a split of two or more tabs. Null clears the tint.
public sealed record TintSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId, BrandColor? Tint) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Identifying(turn.Basis, SpaceId, GroupId, turn.Now, group => group with { Tint = Tint },
            (group, changedAt) => group with { TintModifiedAt = changedAt });

    #endregion
}
