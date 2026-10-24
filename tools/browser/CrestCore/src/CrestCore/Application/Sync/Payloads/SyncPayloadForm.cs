namespace CrestCore.Application;

/// How a payload or tombstone is spelled: as the journal holds it, with dates
/// in seconds since 2001, or as the cloud holds it, with dates in seconds since
/// 1970 and keys in order. Every client reads both the same way.
internal sealed class SyncPayloadForm {
    #region Static Variables

    /// The journal's form, which the Apple clients' default encoder wrote.
    public static readonly SyncPayloadForm Journal = new(name: "journal", readsUnixSeconds: false, sortsKeys: false);

    /// The form of the CloudKit `payload` and `tombstone` fields.
    public static readonly SyncPayloadForm Cloud = new(name: "cloud", readsUnixSeconds: true, sortsKeys: true);

    public static IReadOnlyList<SyncPayloadForm> All { get; } = [Journal, Cloud];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether dates are seconds since 1970 rather than since 2001.
    private readonly bool readsUnixSeconds;

    /// Whether an object's keys are written in ordinal order.
    public bool SortsKeys { get; }

    #endregion

    #region Constructors

    private SyncPayloadForm(string name, bool readsUnixSeconds, bool sortsKeys) {
        Name = name;
        this.readsUnixSeconds = readsUnixSeconds;
        SortsKeys = sortsKeys;
    }

    #endregion

    #region Actions - Dates

    /// The moment `seconds` names in this form.
    public SyncTime Time(double seconds) => readsUnixSeconds ? SyncTime.FromUnixSeconds(seconds) : new(seconds);

    /// `time` as this form spells it.
    public double Seconds(SyncTime time) => readsUnixSeconds ? time.UnixSeconds : time.ReferenceSeconds;

    #endregion
}
