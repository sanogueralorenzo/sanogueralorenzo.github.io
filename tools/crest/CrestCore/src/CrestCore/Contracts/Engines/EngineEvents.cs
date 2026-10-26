namespace CrestCore.Contracts;

#region Downloads

/// A download the engine runs for one of Crest's profiles: the page it came
/// from, its file and progress, and a warning the person may override while it
/// is still the one `ApprovalToken` names. A failed download says what
/// interrupted it, and `FailureDetail` is the engine's own description of
/// that. `DownloadId` is the engine's own name for it within its profile.
public sealed record EngineDownload(string DownloadId, Guid ProfileId, Guid? SourcePageId, string Filename, string? Path,
    long Received, long Total, DateTimeOffset StartedAt, bool Restored, bool Paused, EngineDownloadState State,
    EngineDownloadWarning? Warning, EngineDownloadInterruption? Interruption, string? FailureDetail, string ApprovalToken,
    bool CanPause = false, bool CanResume = false);

/// What stopped an engine download before its file was saved.
public enum EngineDownloadInterruption {
    /// The connection failed, timed out or went away.
    Network,

    /// The server refused the file or could not provide it.
    Server,

    /// The disk has no room for the file.
    NoSpace,

    /// The file could not be written where it was going.
    FileAccess,

    /// Anything else, such as the engine stopping.
    Other
}

/// Where an engine download stands.
public enum EngineDownloadState {
    /// Its file is not chosen yet.
    Preparing,

    Downloading,

    /// It waits for the person to keep a file its warning describes.
    AwaitingApproval,

    Finished,
    Canceled,

    /// It stopped: `Failure` or its warning says why.
    Failed,

    /// A download the site sent without the person's gesture, which the
    /// Space's choices refused. It waits for the person to retry it, which
    /// the engine hears as an approval of its `ApprovalToken` and replays
    /// under the same `DownloadId`.
    Blocked
}

#endregion
