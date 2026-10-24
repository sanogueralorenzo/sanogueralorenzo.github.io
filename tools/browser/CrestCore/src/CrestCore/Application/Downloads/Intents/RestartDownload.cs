using CrestCore.Application;

namespace CrestCore.Contracts;

/// Retrying a blocked automatic download starts the same record again from
/// nothing and counts as news for the downloads badge.
public sealed record RestartDownload(Guid DownloadId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.Restart(DownloadId), changes);

    /// A download the site's choices blocked is replayed by its engine as the
    /// person's own download, under the same name.
    internal override void Before(EngineDownloads engineDownloads, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (engineDownloads.Tracking(DownloadId) is not { IsLive: true, IsBlocked: true } download) return;
        download.IsBlocked = false;
        issue(download.Engine, new ApproveEngineDownload(download.ProfileId, download.EngineId, download.ApprovalToken ?? ""));
        download.ApprovalToken = null;
    }

    #endregion
}
