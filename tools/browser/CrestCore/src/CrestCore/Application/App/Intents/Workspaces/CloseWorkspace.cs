using CrestCore.Application;

namespace CrestCore.Contracts;

/// Closes a workspace and every workspace that borrows a Space from it, the
/// borrowers first. For each, the core publishes `PageRemoved` for its pages,
/// asking their engines to close what they still hold, then `WindowClosed` for
/// each window over it, then `WorkspaceClosed`. Its session takes no edits
/// afterwards. The device keeps the saved records of its windows, so a later
/// launch restores them: closing a workspace is not closing its windows one by
/// one. A workspace that is not open publishes nothing.
public sealed record CloseWorkspace(Guid WorkspaceId) : WorkspaceIntent {
    #region Actions - App

    internal override void Apply(CrestApp app) => app.Close(WorkspaceId);

    #endregion
}
