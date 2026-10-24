using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Reopens an archived tab as an open tab of its Space and removes its entry
/// from the archive. The window that asked shows it, when that window is open
/// over the workspace.
public sealed record RestoreArchivedTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Reopens the archived tab as an open tab, which the issuing window shows.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var index = space.ArchivedTabs.ToList().FindIndex(archived => archived.Tab.Id == TabId);
        if (index < 0) throw new Rejected(new UnknownArchivedTab(TabId));
        if (turn.Basis.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == TabId)))
            throw new Rejected(new TabAlreadyExists(TabId));
        var remaining = space with { ArchivedTabs = [.. space.ArchivedTabs.Where((_, position) => position != index)] };
        var edited = BrowserTabCollection.Restore(remaining);
        var restored = edited.RestoreArchived(space.ArchivedTabs[index].Tab, turn.Now);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId)).ShowTab(space.Id, restored.Id);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(remaining)), SyncStaging.Creation, followUp);
    }

    #endregion
}
