using CrestCore.Application;

namespace CrestCore.Contracts;

/// A live download finished with the bytes actually written, when known.
public sealed record FinishDownload(Guid DownloadId, long? FinalByteCount) : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.Finish(DownloadId, FinalByteCount), changes);

    #endregion
}
