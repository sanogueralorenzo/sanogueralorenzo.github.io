using CrestCore.Application;

namespace CrestCore.Contracts;

/// The session the import would leave its workspace with, without importing
/// anything: what a person sees before they import. It shows Spaces this
/// process has not unlocked, since an import that changes one waits until it
/// is; otherwise it is refused as the import would be.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ImportPreview(ImportWorkspace Import) : Query<ImportedWorkspace> {
    #region Actions - Answering

    /// Finishing setup previews its import the same way.
    internal override ImportedWorkspace Answer(CrestApp app) => app.Device.Workspace(Import.WorkspaceId).Preview(Import, app.Clock.Now);

    #endregion
}
