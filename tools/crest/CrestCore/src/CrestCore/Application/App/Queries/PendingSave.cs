using CrestCore.Application;

namespace CrestCore.Contracts;

/// <summary>Which file revision the core has handed its session file and not yet
/// written, so a caller can wait until it is on disk. The stored session's edits
/// and this device's saved windows each take one.</summary>
public sealed record PendingSave : Query<PendingSaveRevision> {
    #region Actions - Answering

    internal override PendingSaveRevision Answer(CrestApp app) =>
        new(app.Storage?.PendingRevision is { } revision ? checked((long)revision) : null);

    #endregion
}
