using CrestCore.Application;

namespace CrestCore.Contracts;

/// One engine progress sample for a transfer. `Estimator` is the state the
/// previous reading returned, or null for the first sample. `Uptime` is a
/// monotonic clock in seconds; `FractionCompleted` is used only while no total
/// is known.
public sealed record DownloadProgress(DownloadTransferEstimator? Estimator, long CompletedUnitCount, long TotalUnitCount,
    double FractionCompleted, bool IsPaused, double Uptime) : Query<DownloadProgressReading> {
    #region Actions - Answering

    /// The engines' downloads ask the ledger the same question.
    internal override DownloadProgressReading Answer(CrestApp app) => app.Downloads.Answer(this);

    #endregion
}
