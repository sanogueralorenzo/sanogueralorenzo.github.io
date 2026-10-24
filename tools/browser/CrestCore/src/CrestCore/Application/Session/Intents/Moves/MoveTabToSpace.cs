using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Moves a tab to the Space `DestinationSpaceId`: into `FolderId` or to the
/// top level of `Placement`'s section there, or of the section it is in,
/// before the tab `BeforeTabId` or after the section's last tab. A split
/// member leaves its split. The window that asked shows the tab it showed
/// before in the Space the tab left, when it showed the moved one; when
/// `Follows`, it moves to the destination and shows the moved tab. Saved with
/// the sync journal before the intent returns. Refused with `AlreadyInSpace`
/// for the Space the tab is in, with `TabLimitReached` or `PinnedTabsFull`
/// when the destination has no room, and with `UnknownFolder` or
/// `InvalidFolderPlacement` for a folder that is not there or not in the
/// section.
public sealed record MoveTabToSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid DestinationSpaceId,
    TabPlacement? Placement, Guid? FolderId, Guid? BeforeTabId, bool Follows) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Moves the tab to another Space of this workspace. The issuing window
    /// gives up the tab it showed for the one it showed before, and when the
    /// intent follows the tab it moves to the destination and shows it there.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (DestinationSpaceId == SpaceId) throw new Rejected(new AlreadyInSpace(SpaceId));
        var space = workspace.Editable(turn.Basis, SpaceId);
        var destination = workspace.Editable(turn.Basis, DestinationSpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var receiving = BrowserTabCollection.Restore(destination);
        _ = edited.Tab(TabId);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shownThere = followUp.Window?.Tab(destination.Id);
        var fallback = followUp.FallbackAfterDismissing(space.Id, TabId,
            space.Tabs.Select(tab => tab.Id).Where(id => id != TabId).ToHashSet());
        var shown = edited.TransferTo(receiving, TabId, followUp.Window?.Tab(space.Id), fallback, Placement,
            FolderId, BeforeTabId, afterSelection: false, shownThere, turn.Now);
        if (Follows) {
            receiving.Tab(TabId).Activate(turn.Now);
            shownThere = TabId;
        }
        edited.PruneSplitMetadata();
        receiving.PruneSplitMetadata();
        followUp.ShowTab(space.Id, shown).ShowTab(destination.Id, shownThere);
        if (Follows) followUp.ShowSpace(destination.Id);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(space), receiving.Capture(destination)),
            SyncStaging.Transfer, followUp);
    }

    #endregion
}
