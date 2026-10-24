using CrestCore.Application;

namespace CrestCore.Contracts;

/// Chooses how a tab's icon is filled: from its page as the page changes, with
/// the page's favicon pulled once and kept, or with `Emoji`. A pulled favicon
/// keeps `Accent`, the color the page's theme puts behind it, and the tab
/// wears the image the issuer holds, which it offers with the intent; any
/// other choice drops the tab's image. Refused with `InvalidTabIcon` when the
/// mode can make no icon from what the intent gives.
public sealed record ChooseTabIcon(Guid WorkspaceId, Guid SpaceId, Guid TabId, TabIconMode Mode, string? Emoji,
    TabIconAccent? Accent) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// A tab that pulls its page's favicon wears the image the issuer offered,
    /// and any other choice drops its image. The assignment is published even
    /// when the choice changes nothing else, so a favicon pulled again from the
    /// same page replaces the image the tab wears.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var adopts = false;
        var edit = workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited =>
            adopts = edited.Tab(TabId).ChooseIcon(Mode, Emoji, Accent));
        return edit with { Events = new([], new SessionFaviconUpdate(TabId, adopts)) };
    }

    #endregion
}
