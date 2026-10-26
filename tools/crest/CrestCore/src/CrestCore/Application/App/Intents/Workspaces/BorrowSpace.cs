using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record BorrowSpace(Guid WorkspaceId, Guid SpaceId, Guid ProfileId) : WorkspaceIntent {
    #region Actions - App

    internal override void Apply(CrestApp app) {
        var owner = app.Device.Workspace(WorkspaceId);
        app.Device.Attach(owner.Borrow(SpaceId, ProfileId), app.Ids.Next());
    }

    #endregion
}
