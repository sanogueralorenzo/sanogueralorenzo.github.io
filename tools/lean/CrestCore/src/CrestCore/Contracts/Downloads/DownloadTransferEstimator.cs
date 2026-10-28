namespace CrestCore.Contracts;

/// Turns event-driven engine progress samples into stable row telemetry.
///
/// Samples accumulate until enough time has elapsed for a useful rate, which
/// is then smoothed with an exponential moving average. Reported byte counts
/// never move backwards. A total that received bytes disprove is discarded for
/// the rest of the transfer instead of producing a count larger than its total.
/// `Initial` is the state before the first sample; callers keep the returned
/// state per transfer and pass it back with the next sample.
public sealed record DownloadTransferEstimator(long PublishedBytes, long? KnownTotalBytes, bool TotalIsUnreliable,
    long? MeasurementBytes, double? MeasurementUptime, double? SmoothedBytesPerSecond) {
    #region Variables

    public const double MinimumRateInterval = 0.15;
    public const double SmoothingWeight = 0.25;
    public const double MinimumUsefulEstimate = 0.5;
    public const double MaximumUsefulEstimate = 7 * 24 * 60 * 60;

    public static DownloadTransferEstimator Initial { get; } = new(0, null, false, null, null, null);

    public bool IsValid => PublishedBytes >= 0 && (KnownTotalBytes ?? 1) > 0 && (MeasurementBytes ?? 0) >= 0
        && MeasurementBytes.HasValue == MeasurementUptime.HasValue
        && (MeasurementUptime is not { } uptime || double.IsFinite(uptime))
        && (SmoothedBytesPerSecond is not { } rate || double.IsFinite(rate) && rate > 0);

    #endregion

    #region Actions - Transfers

    /// `uptime` is a monotonic clock in seconds; `fractionCompleted` is used only
    /// while no total is known.
    public DownloadProgressReading Sample(long completedUnitCount, long totalUnitCount, double fractionCompleted,
        bool isPaused, double uptime) {
        if (!IsValid || !double.IsFinite(uptime)) throw new Rejected(new InvalidDownloadSample());
        long published = Math.Max(PublishedBytes, Math.Max(completedUnitCount, 0));
        var next = (this with { PublishedBytes = published }).WithReportedTotal(totalUnitCount);
        next = isPaused
            ? next with { MeasurementBytes = published, MeasurementUptime = uptime, SmoothedBytesPerSecond = null }
            : next.WithRate(uptime);

        double progress = next.KnownTotalBytes is { } total and > 0
            ? Normalized((double)published / total)
            : Normalized(fractionCompleted);
        double? rate = isPaused ? null : next.SmoothedBytesPerSecond;
        var telemetry = new DownloadTelemetry(published, next.KnownTotalBytes, rate, next.EstimatedTimeRemaining(rate), isPaused);
        return new(next, telemetry, progress);
    }

    /// Progress is always published within [0, 1]; an unreadable value is 0.
    public static double Normalized(double progress) => double.IsFinite(progress) ? Math.Clamp(progress, 0, 1) : 0;

    private DownloadTransferEstimator WithReportedTotal(long reportedTotal) {
        if (TotalIsUnreliable || reportedTotal <= 0) return this;
        if (reportedTotal < PublishedBytes) return this with { KnownTotalBytes = null, TotalIsUnreliable = true };
        return this with { KnownTotalBytes = Math.Max(KnownTotalBytes ?? 0, reportedTotal) };
    }

    private DownloadTransferEstimator WithRate(double uptime) {
        if (MeasurementBytes is not { } measuredBytes || MeasurementUptime is not { } measuredAt)
            return this with { MeasurementBytes = PublishedBytes, MeasurementUptime = uptime };
        double elapsed = uptime - measuredAt;
        if (!double.IsFinite(elapsed) || elapsed < MinimumRateInterval) return this;
        long transferred = PublishedBytes - measuredBytes;
        var measured = this with { MeasurementBytes = PublishedBytes, MeasurementUptime = uptime };
        if (transferred <= 0) return measured;
        double instantaneous = transferred / elapsed;
        if (!double.IsFinite(instantaneous) || instantaneous <= 0) return measured;
        return measured with {
            SmoothedBytesPerSecond = SmoothedBytesPerSecond is { } smoothed
                ? smoothed * (1 - SmoothingWeight) + instantaneous * SmoothingWeight
                : instantaneous
        };
    }

    private double? EstimatedTimeRemaining(double? rate) {
        if (KnownTotalBytes is not { } total || rate is not { } speed || !double.IsFinite(speed) || speed <= 0) return null;
        long remaining = Math.Max(total - PublishedBytes, 0);
        if (remaining <= 0) return null;
        double estimate = remaining / speed;
        return double.IsFinite(estimate) && estimate is >= MinimumUsefulEstimate and <= MaximumUsefulEstimate ? estimate : null;
    }

    #endregion
}
