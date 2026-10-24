using CrestCore.Application;

namespace CrestCore.Contracts;

/// Clears one record. Files already written stay on disk; the caller refuses to
/// clear a record whose transfer it still owns.
public sealed record RemoveDownload(Guid DownloadId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        Downloads.Removed(downloads.Ledger.Remove(DownloadId) ? [DownloadId] : [], changes);

    /// A download its engine no longer runs, or one the site's choices
    /// blocked, leaves the engine's list.
    internal override void Before(EngineDownloads engineDownloads, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (engineDownloads.Tracking(DownloadId) is not { } download || download.IsLive && !download.IsBlocked) return;
        issue(download.Engine, new RemoveEngineDownload(download.ProfileId, download.EngineId));
        engineDownloads.End(download, changes);
    }

    #endregion
}
