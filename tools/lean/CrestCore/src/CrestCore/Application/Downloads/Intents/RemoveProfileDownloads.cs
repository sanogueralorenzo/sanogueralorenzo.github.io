using CrestCore.Application;

namespace CrestCore.Contracts;

/// Deleting a profile's data removes every record it owns, live or not. The
/// caller cancels the matching transfers.
public sealed record RemoveProfileDownloads(Guid ProfileId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        Downloads.Removed(downloads.Ledger.RemoveProfile(ProfileId), changes);

    /// Deleting a profile's data cancels and clears each of its downloads on
    /// its engine.
    internal override void Before(EngineDownloads engineDownloads, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        foreach (var download in engineDownloads.TrackedDownloads.Where(download => download.ProfileId == ProfileId)) {
            if (download.IsLive) issue(download.Engine, new CancelEngineDownload(download.ProfileId, download.EngineId));
            issue(download.Engine, new RemoveEngineDownload(download.ProfileId, download.EngineId));
            engineDownloads.End(download, changes);
        }
    }

    #endregion
}
