using CrestCore.Application;

namespace CrestCore.Contracts;

/// A live download was canceled.
public sealed record CancelDownload(Guid DownloadId, string Message) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.Cancel(DownloadId, Message), changes);

    /// A download its engine runs is cancelled there.
    internal override void Before(EngineDownloads engineDownloads, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (engineDownloads.Tracking(DownloadId) is not { IsLive: true, IsBlocked: false } download) return;
        issue(download.Engine, new CancelEngineDownload(download.ProfileId, download.EngineId));
        engineDownloads.End(download, changes);
    }

    #endregion
}
