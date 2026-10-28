using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record ExportWorkspace(Guid WorkspaceId, ExportFormat Format) : Query<ExportedDocument> {
    #region Variables

    /// Only reading the session holds the lock; writing the file reads immutable records outside it.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// The file an export writes. Only reading the session holds the lock;
    /// writing the file reads immutable records outside it.
    internal override ExportedDocument Answer(CrestApp app) {
        SessionState session;
        lock (app.Gate) session = app.Device.Workspace(WorkspaceId).Exported();
        return app.Portability.Export(session, Format);
    }

    #endregion
}
