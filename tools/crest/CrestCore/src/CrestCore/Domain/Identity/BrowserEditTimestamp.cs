namespace CrestCore.Domain;

/// Tab and split conflict clocks use the same millisecond precision on every device.
public static class BrowserEditTimestamp {
    #region Actions - Identity

    public static double NormalizeUnixSeconds(double seconds) {
        if (!double.IsFinite(seconds))
            throw new ArgumentOutOfRangeException(nameof(seconds), seconds, "A time is a finite number of seconds.");
        return Math.Round(seconds * 1000, MidpointRounding.AwayFromZero) / 1000;
    }

    public static DateTimeOffset Normalize(DateTimeOffset value) => DateTimeOffset.FromUnixTimeMilliseconds(
        (long)Math.Round((value - DateTimeOffset.UnixEpoch).TotalMilliseconds, MidpointRounding.AwayFromZero));

    #endregion
}
