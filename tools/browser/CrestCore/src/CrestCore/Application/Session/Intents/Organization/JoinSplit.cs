using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Adds a tab to the split of `TargetTabId`, or makes the two a split, at
/// member `Index` or after the others. A saved or pinned tab stays where it is
/// and an open copy joins in its place, with an identity the core gives it,
/// showing what its source's page shows now; each copy is published as
/// `TabCopied`. The window that asked shows the joined tab in its Space.
public sealed record JoinSplit(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid TargetTabId, int? Index)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        return workspace.Joining(turn.Basis, space, BrowserTabCollection.Restore(space), WindowId, TabId, TargetTabId,
            Index, turn.Pages, turn.Now, turn.Ids);
    }

    #endregion
}
