using CrestCore.Application;

namespace CrestCore.Contracts;

/// Opens a borrowed workspace that shows the Space `SpaceId` of the workspace
/// `WorkspaceId` with tabs, folders, history and archive of its own, and
/// publishes `WorkspaceOpened` for it. The borrowed Space keeps its owner's
/// profile, settings and access grants, and follows its owner: each edit of
/// the owner's Space settings reaches it in the same answer, and it closes
/// once its owner no longer lends that Space with that profile. It keeps
/// nothing: it is never saved or synced.
///
/// Refused with `UnknownWorkspace`, `UnknownSpace`, `SpaceBeingDeleted`,
/// `SpaceLocked`, `BorrowedProfileRequiresOwner` when `WorkspaceId` borrows its
/// own Space, and `SpaceProfileChanged` when the Space no longer uses the
/// profile `ProfileId` names.
public sealed record BorrowSpace(Guid WorkspaceId, Guid SpaceId, Guid ProfileId) : WorkspaceIntent {
    #region Actions - App

    internal override void Apply(CrestApp app) {
        var owner = app.Device.Workspace(WorkspaceId);
        app.Device.Attach(owner.Borrow(SpaceId, ProfileId), app.Ids.Next());
    }

    #endregion
}
