using CrestCore.Application;

namespace CrestCore.Contracts;

/// Names a split of two or more tabs. A blank or null name clears it.
public sealed record NameSplit(Guid WorkspaceId, Guid SpaceId, Guid GroupId, string? Name) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// A blank name clears it; a name is kept trimmed.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Identifying(turn.Basis, SpaceId, GroupId, turn.Now, group =>
            group with { CustomTitle = string.IsNullOrWhiteSpace(Name) ? null : Name.Trim() },
            (group, changedAt) => group with { TitleModifiedAt = changedAt });

    #endregion
}
