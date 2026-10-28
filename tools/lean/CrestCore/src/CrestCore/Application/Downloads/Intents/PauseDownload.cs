using CrestCore.Application;

namespace CrestCore.Contracts;

/// Requests a pause. The row changes only when its engine confirms the pause.
public sealed record PauseDownload(Guid DownloadId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) { }

    internal override void Before(EngineDownloads engineDownloads, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (engineDownloads.Tracking(DownloadId) is not { IsLive: true } download
            || engineDownloads.Controllable(download) is not { CanPause: true }) return;
        issue(download.Engine, new PauseEngineDownload(download.ProfileId, download.EngineId));
    }

    #endregion
}
