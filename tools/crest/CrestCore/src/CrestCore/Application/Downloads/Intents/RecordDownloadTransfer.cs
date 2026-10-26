using CrestCore.Application;

namespace CrestCore.Contracts;

/// One transfer reading for a live download. Progress never moves backwards.
public sealed record RecordDownloadTransfer(Guid DownloadId, DownloadTelemetry Telemetry, double Progress)
    : DownloadIntent {
    #region Actions - Downloads

    internal override void Apply(Downloads downloads, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.RecordTransfer(DownloadId, Telemetry, Progress), changes);

    #endregion
}
