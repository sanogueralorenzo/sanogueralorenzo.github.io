using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Archives every open tab of a Space and keeps its saved and pinned tabs.
/// The window that asked shows the tab its Space falls back to. Refused with
/// `NoCurrentTabs` when the Space has no open tab.
public sealed record ClearCurrentTabs(Guid WorkspaceId, Guid WindowId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Archives the Space's open tabs. The issuing window shows the tab it
    /// showed there when that tab stays, or the one the Space falls back to.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var open = edited.Tabs.Where(tab => !tab.Placement.IsDurable).Select(tab => tab.Id).ToArray();
        if (open.Length == 0) throw new Rejected(new NoCurrentTabs(space.Id));
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var selected = edited.DismissTabs(open, followUp.Window?.Tab(space.Id), null, turn.Now, deleting: false, ensureSelection: true,
            resetArchivePlacement: false);
        edited.PruneSplitMetadata();
        followUp.ShowTab(space.Id, selected);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(space)), SyncStaging.Creation, followUp);
    }

    #endregion
}
