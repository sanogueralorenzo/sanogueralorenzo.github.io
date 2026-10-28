using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Closes a tab the way its section closes one: an open tab is archived, and
/// a saved or pinned tab keeps its place and last location and puts its page
/// away. A window that showed the tab returns to the tab it showed before.
/// Refused with `LastStartPage`
/// for the Start Page when it is its Space's only tab, which leaves only the
/// window to close.
public sealed record CloseTab(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Closes the tab the way its section closes one: a saved or pinned tab
    /// puts its page away, and an open tab is archived. A window that showed
    /// the tab returns to the one it showed before; one that put a saved or
    /// pinned tab away skips its split, whose other members would present it
    /// again. A page put away keeps what brings it back at its last location,
    /// and the window that asked lets it go.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var edited = BrowserTabCollection.Restore(space);
        var tab = edited.Tab(TabId);
        var action = TabDismissalAction.Of(tab.Placement, tab.Content.IsStartPage, space.Tabs.Count);
        if (action.ClosesWindow) throw new Rejected(new LastStartPage(tab.Id));
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        var shown = followUp.Window?.Tab(space.Id);
        Guid? selected;
        SessionTabEvents? events = null;
        if (action.KeepsTab) {
            var group = tab.SplitGroupId;
            var fallback = followUp.FallbackAfterDismissing(space.Id, tab.Id, space.Tabs
                .Where(candidate => candidate.Id != tab.Id && (group is null || candidate.SplitGroupId != group))
                .Select(candidate => candidate.Id).ToHashSet());
            selected = shown == tab.Id ? fallback : shown;
            events = SessionTabEvents.None with { PutAway = new(WindowId, space.Id, tab.Id, KeepsState: true) };
        } else {
            var fallback = followUp.FallbackAfterDismissing(space.Id, tab.Id, space.Tabs.Select(candidate => candidate.Id).ToHashSet());
            selected = edited.DismissTabs([tab.Id], shown, fallback, turn.Now, deleting: false, ensureSelection: false,
                resetArchivePlacement: false);
        }
        followUp.ShowTab(space.Id, selected);
        return new(turn.Basis.Replacing(edited.Capture(space)), SyncStaging.Creation, followUp, events);
    }

    #endregion
}
