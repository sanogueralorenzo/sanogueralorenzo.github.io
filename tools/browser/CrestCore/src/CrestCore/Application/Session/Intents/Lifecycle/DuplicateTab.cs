using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Copies a tab into `Placement`'s section, or among the open tabs when null,
/// with an identity the core gives it, published as `TabCopied`. A copy of a
/// web page starts from where the source's page is now. When `Shows`, the
/// window that asked shows the copy and its Space.
public sealed record DuplicateTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, TabPlacement? Placement, bool Shows)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Copies the tab, starting from where its page is now; see
    /// `StartFromSourcePage`. The issuing window shows the copy when the
    /// intent asks.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        if (edited.Tab(TabId).Content.IsStartPage) throw new Rejected(new StartPageNotCopied(TabId));
        var copy = edited.DuplicateTab(TabId, turn.Ids, turn.Now, Placement ?? TabPlacement.Current);
        workspace.StartFromSourcePage(copy, TabId, WindowId, turn.Pages);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (Shows) followUp.ShowTab(space.Id, copy.Id).ShowSpace(space.Id);
        return new(NativeSessionAuthority.Replacing(turn.Basis, edited.Capture(space)), SyncStaging.Creation, followUp,
            new([new SessionTabCopy(TabId, copy.Id)], null));
    }

    #endregion
}
