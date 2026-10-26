using CrestCore.Application;

namespace CrestCore.Contracts;

[MessageLimit(64 * 1024 * 1024)]
public sealed record ImportPreview(ImportWorkspace Import) : Query<ImportedWorkspace> {
    #region Actions - Answering

    /// Finishing setup previews its import the same way.
    internal override ImportedWorkspace Answer(CrestApp app) => app.Device.Workspace(Import.WorkspaceId).Preview(Import, app.Clock.Now);

    #endregion
}
