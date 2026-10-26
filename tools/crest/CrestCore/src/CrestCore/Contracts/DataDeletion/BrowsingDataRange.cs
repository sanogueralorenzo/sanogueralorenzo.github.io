namespace CrestCore.Contracts;

/// How far back clearing a Space's browsing data reaches. A range travels as
/// its index in `All`, so `All` is append-only.
public sealed class BrowsingDataRange {
    #region Static Variables

    public static readonly BrowsingDataRange LastHour = new(name: "lastHour", title: "Last Hour", span: TimeSpan.FromHours(1));
    public static readonly BrowsingDataRange LastDay = new(name: "lastDay", title: "Last 24 Hours", span: TimeSpan.FromDays(1));
    public static readonly BrowsingDataRange LastWeek = new(name: "lastWeek", title: "Last 7 Days", span: TimeSpan.FromDays(7));
    public static readonly BrowsingDataRange LastFourWeeks = new(name: "lastFourWeeks", title: "Last 4 Weeks",
        span: TimeSpan.FromDays(28));
    public static readonly BrowsingDataRange AllTime = new(name: "allTime", title: "All Time", span: null);

    public static IReadOnlyList<BrowsingDataRange> All { get; } = [LastHour, LastDay, LastWeek, LastFourWeeks, AllTime];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the time range picker calls the range.
    [Localized]
    public string Title { get; }

    /// How far back the range reaches, or nil for everything.
    private readonly TimeSpan? span;

    #endregion

    #region Constructors

    private BrowsingDataRange(string name, string title, TimeSpan? span) {
        Name = name;
        Title = title;
        this.span = span;
    }

    #endregion

    #region Actions - Time

    /// The earliest moment the range covers when it ends at `now`, or nil
    /// when it covers everything.
    internal DateTimeOffset? Since(DateTimeOffset now) => span is { } reach ? now - reach : null;

    #endregion
}
