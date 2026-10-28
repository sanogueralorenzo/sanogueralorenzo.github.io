namespace CrestCore.Application;

/// A moment a synced record carries, held exactly as the Apple clients hold a
/// date: seconds since 2001 as a double. The journal writes those seconds; the
/// cloud writes seconds since 1970, which the clients compute by adding the
/// seconds between the epochs, so converting with the same arithmetic keeps
/// every client's reading of a date bit for bit.
internal readonly record struct SyncTime(double ReferenceSeconds) {
    #region Static Variables

    /// Seconds from 1970 to 2001.
    private const double EpochDistance = 978_307_200;

    #endregion

    #region Variables

    /// The moment in seconds since 1970, as the cloud spells it.
    public double UnixSeconds => ReferenceSeconds + EpochDistance;

    public DateTimeOffset Moment => StoredSessionCodec.Date(ReferenceSeconds);

    #endregion

    #region Actions - Conversion

    /// The moment `seconds` after 1970 names. Subtracting the epochs is exact
    /// for every date after 2001, so a moment read from the cloud converts back
    /// to the same Unix seconds.
    public static SyncTime FromUnixSeconds(double seconds) => new(seconds - EpochDistance);

    /// The moment rounded to whole milliseconds in Unix time, as the clients
    /// round the clocks of a split's fields.
    public SyncTime ToWholeMilliseconds() => FromUnixSeconds(Math.Round(UnixSeconds * 1_000, MidpointRounding.AwayFromZero) / 1_000);

    #endregion
}
