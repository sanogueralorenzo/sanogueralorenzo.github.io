namespace CrestCore.Application;

/// The times imports and Crest browser-data files carry, converted the way the
/// Apple platforms' dates are: seconds since 2001 as a double, so a time read
/// here is stored exactly as the platform would have stored it.
internal static class ImportDate {
    #region Static Variables

    /// Seconds from 1970 to 2001.
    private const double ReferenceOffset = 978_307_200;

    /// Seconds from 1601, where Windows and Chromium count from, to 1970.
    private const double WindowsOffset = 11_644_473_600;

    #endregion

    #region Actions - Reading

    /// A time given in seconds since 1970, or null when it is not a finite
    /// time.
    public static DateTimeOffset? FromUnixSeconds(double seconds) {
        double reference = seconds - ReferenceOffset;
        return double.IsFinite(reference) ? StoredSessionCodec.Date(reference) : null;
    }

    /// A time given in milliseconds since 1970.
    public static DateTimeOffset? FromUnixMilliseconds(double milliseconds) => FromUnixSeconds(milliseconds / 1_000);

    /// A time given in microseconds since 1601.
    public static DateTimeOffset? FromWindowsMicroseconds(double microseconds) =>
        FromUnixSeconds(microseconds / 1_000_000 - WindowsOffset);

    /// A time given in seconds since 1970 or, when it is too large to be
    /// seconds, in milliseconds.
    public static DateTimeOffset? FromUnixSecondsOrMilliseconds(double value) =>
        FromUnixSeconds(value > 10_000_000_000 ? value / 1_000 : value);

    /// A time given in whichever unit its size suggests: microseconds since
    /// 1601, microseconds, milliseconds or seconds since 1970.
    public static DateTimeOffset? FromAnyUnit(double value) => value switch {
        > 10_000_000_000_000_000 => FromWindowsMicroseconds(value),
        > 10_000_000_000_000 => FromUnixSeconds(value / 1_000_000),
        > 10_000_000_000 => FromUnixMilliseconds(value),
        _ => FromUnixSeconds(value)
    };

    /// A time given in seconds or milliseconds since 1970 or, when it is too
    /// small to be a time since 2001 counted that way, in seconds since 2001,
    /// as apps on Apple's platforms keep them.
    public static DateTimeOffset? FromUnixOrReferenceSeconds(double value) =>
        value is > 0 and < ReferenceOffset ? FromReferenceSeconds(value) : FromUnixSecondsOrMilliseconds(value);

    /// A time given in seconds since 2001, as property lists keep them.
    public static DateTimeOffset? FromReferenceSeconds(double seconds) =>
        double.IsFinite(seconds) ? StoredSessionCodec.Date(seconds) : null;

    #endregion

    #region Actions - Writing

    /// Seconds since 1970.
    public static double UnixSeconds(DateTimeOffset date) => StoredSessionCodec.Seconds(date) + ReferenceOffset;

    /// Milliseconds since 1970, as Crest browser-data files keep times.
    public static double UnixMilliseconds(DateTimeOffset date) => UnixSeconds(date) * 1_000;

    #endregion
}
