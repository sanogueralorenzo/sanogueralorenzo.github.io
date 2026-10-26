using CrestCore.Application;

namespace CrestCore.Contracts;

/// Copies the tabs a person selected in a window to the end of the open tabs,
/// in the order the sidebar lists them, with identities the core gives them,
/// each published as `TabCopied`. A copy of a web page starts from where its
/// source's page is now, preferring the page the window shows. The copies of a
/// split's members form a split of their own, named, drawn and tinted as the
/// source split is.
public sealed record DuplicateTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var batch = workspace.Selecting(turn.Basis, WindowId, SpaceId, Selection);
        var copies = batch.Edited.DuplicateSelected(batch.Selected, turn.Ids, turn.Now);
        return batch.Result(turn.Basis, SyncStaging.Batch, workspace.StartingCopies(batch, copies, WindowId, turn.Pages));
    }

    #endregion
}
