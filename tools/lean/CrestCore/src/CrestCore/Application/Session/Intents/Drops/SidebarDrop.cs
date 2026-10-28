using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Drops what a person lifted in a window's sidebar, the tabs and folders
/// `Selection` holds as the window saw them, in the Space the window shows.
/// The core commits a drop as the edit its kind names, and decides which in
/// one place: a lift of one tab moves that tab alone, leaving its split, as
/// dragging a tab always has; any other lift acts on the selection whole, as
/// the batch intents do, and a split member brings its split along. Refused
/// with the rule of the edit it commits, and for a lift of pinned tabs with
/// others, `PinnedTabsDragAlone`. `DropTargets` answers, as the lift begins,
/// which drops each target takes.
public abstract record SidebarDrop(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : SessionIntent(WorkspaceId) {
    #region Abstract Methods

    /// The intent the drop commits for `lift`, the selection it lifts resolved
    /// in the Space the window shows. A lift of one tab moves that tab alone
    /// and leaves its split, as dragging a tab does; any other lift is a
    /// selection the batch intents act on whole. New identities come from `ids`.
    internal abstract SessionIntent Committed(NativeSessionAuthority.Lift lift, IIdSource ids);

    #endregion

    #region Actions - Session

    /// A drop commits the edit it decides, from the same basis.
    internal sealed override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        Committed(workspace.Lifting(turn.Basis, WindowId, SpaceId, Selection), turn.Ids).Edit(workspace, turn);

    #endregion
}
