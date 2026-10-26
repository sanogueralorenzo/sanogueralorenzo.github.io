using CrestCore.Application;

namespace CrestCore.Contracts;

/// Opening a profile's downloads acknowledges its records without clearing them.
public sealed record AcknowledgeDownloads(Guid ProfileId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) {
        foreach (var download in downloads.Ledger.AcknowledgeProfile(ProfileId)) downloads.Updated(download, changes);
    }

    #endregion
}
