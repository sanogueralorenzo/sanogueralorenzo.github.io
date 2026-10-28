namespace CrestCore.Contracts;

/// Live transfer facts for one download row. They travel with the record so
/// every presentation sees one snapshot, and become inactive as soon as the
/// transfer stops. `EstimatedTimeRemaining` is in seconds.
public sealed record DownloadTelemetry(long BytesReceived, long? TotalBytes, double? BytesPerSecond,
    double? EstimatedTimeRemaining, bool IsPaused) {
    #region Variables

    public static DownloadTelemetry Empty { get; } = new(0, null, null, null, false);

    public bool IsValid => BytesReceived >= 0 && (TotalBytes ?? 0) >= 0
        && IsMeasure(BytesPerSecond) && IsMeasure(EstimatedTimeRemaining);

    #endregion

    #region Actions - Transfers

    /// The telemetry a stopped transfer keeps: no rate or estimate, and on
    /// completion a total equal to the bytes actually written.
    public DownloadTelemetry Stopped(long? finalByteCount = null, bool completed = false) {
        long finalBytes = Math.Max(BytesReceived, finalByteCount ?? 0);
        return new(finalBytes, completed ? finalBytes : TotalBytes, null, null, false);
    }

    private static bool IsMeasure(double? value) => value is not { } number || double.IsFinite(number) && number >= 0;

    #endregion
}
