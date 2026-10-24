using CrestCore.Application;

namespace CrestCore.Contracts;

/// Requests recovery using the engine's saved request. A late report alone
/// cannot restart a failed transfer or restore a removed record.
public sealed record ResumeDownload(Guid DownloadId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) { }

    internal override void Before(EngineDownloads engineDownloads, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (engineDownloads.Tracking(DownloadId) is not { ResumeRequested: false } download
            || engineDownloads.Controllable(download) is not { CanResume: true }) return;
        download.ResumeRequested = true;
        issue(download.Engine, new ResumeEngineDownload(download.ProfileId, download.EngineId));
    }

    #endregion
}
