using CrestCore.Domain;

namespace CrestCore.Contracts;

/// How long a Space keeps history, archived tabs or downloads.
///
/// The stored session spells a choice as its `Name`, so a name never changes.
/// A choice travels as its index in `All`, so `All` is append-only.
public sealed class DataRetention {
    #region Variables

    public static readonly DataRetention OneDay = new(name: "oneDay", title: "1 Day", lifetime: TimeSpan.FromDays(1));
    public static readonly DataRetention OneWeek = new(name: "oneWeek", title: "1 Week", lifetime: TimeSpan.FromDays(7));
    public static readonly DataRetention ThirtyDays = new(name: "thirtyDays", title: "30 Days", lifetime: TimeSpan.FromDays(30));
    public static readonly DataRetention NinetyDays = new(name: "ninetyDays", title: "90 Days", lifetime: TimeSpan.FromDays(90));
    public static readonly DataRetention OneYear = new(name: "oneYear", title: "1 Year", lifetime: TimeSpan.FromDays(365));
    public static readonly DataRetention Forever = new(name: "forever", title: "Forever", lifetime: null);

    /// The choices, in the order the settings offer them.
    public static IReadOnlyList<DataRetention> All { get; } = [OneDay, OneWeek, ThirtyDays, NinetyDays, OneYear, Forever];

    public string Name { get; }

    /// What the settings call the choice.
    [Localized]
    public string Title { get; }

    /// How long a record is kept; null keeps it forever.
    public TimeSpan? Lifetime { get; }

    #endregion

    #region Constructors

    private DataRetention(string name, string title, TimeSpan? lifetime) {
        Name = name;
        Title = title;
        Lifetime = lifetime;
    }

    #endregion

    #region Actions - Lookup

    public static DataRetention? Named(string? name) => All.FirstOrDefault(retention => retention.Name == name);

    #endregion

    #region Actions - Expiry

    /// The indices of `timestamps` older than `lifetime` seconds at `now`.
    /// Numeric timestamps keep native Date precision at a retention boundary;
    /// callers apply the returned indices to their existing value snapshots.
    /// Every time is the stored seconds of a date, so each is finite.
    internal static IReadOnlyList<int> Expired(IReadOnlyList<double> timestamps, double now, double lifetime) {
        ArgumentOutOfRangeException.ThrowIfNegative(lifetime);
        return Enumerable.Range(0, timestamps.Count).Where(i => now - timestamps[i] > lifetime).ToArray();
    }

    #endregion
}
