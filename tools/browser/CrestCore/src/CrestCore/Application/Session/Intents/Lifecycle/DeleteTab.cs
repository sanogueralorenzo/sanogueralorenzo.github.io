using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Deletes a tab from any section and keeps it in the archive as an open tab.
/// The window that asked returns to the tab it showed before, or to the tab
/// its Space falls back to.
public sealed record DeleteTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Deletes the tab into the archive as an open tab. The issuing window
    /// shows the tab it showed before, or the one its Space falls back to.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        _ = edited.Tab(TabId);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var fallback = followUp.FallbackAfterDismissing(space.Id, TabId, space.Tabs.Select(tab => tab.Id).ToHashSet());
        var selected = edited.DismissTabs([TabId], followUp.Window?.Tab(space.Id), fallback, turn.Now, deleting: true,
            ensureSelection: true, resetArchivePlacement: true);
        edited.PruneSplitMetadata();
        followUp.ShowTab(space.Id, selected);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(space)), SyncStaging.Deletion, followUp);
    }

    #endregion
}
