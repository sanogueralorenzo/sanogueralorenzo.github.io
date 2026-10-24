using CrestCore.Application;

namespace CrestCore.Contracts;

/// The file `Format` writes of the workspace's Spaces, in their order, as the
/// session holds them now. Passwords, cookies, website storage, permissions,
/// downloads, favicons and extensions are never part of it.
///
/// Refused with `SpaceLocked` while any of its Spaces is locked, since the
/// file would carry that Space's tabs and history, and `ArchiveTooLarge` or
/// `BookmarksTooLarge` when the file would be larger than an import reads.
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
