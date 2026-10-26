using CrestCore.Application;

namespace CrestCore.Contracts;

/// A live download waits for the person's approval.
public sealed record AwaitDownloadApproval(Guid DownloadId) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.AwaitApproval(DownloadId), changes);

    #endregion
}
