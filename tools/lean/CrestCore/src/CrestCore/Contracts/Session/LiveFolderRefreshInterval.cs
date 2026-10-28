namespace CrestCore.Contracts;

/// The refresh periods offered by Zen's live-folder menu.
public sealed class LiveFolderRefreshInterval {
    #region Static Variables

    public static readonly LiveFolderRefreshInterval FifteenMinutes = new("15minutes", 15, "15 minutes");
    public static readonly LiveFolderRefreshInterval ThirtyMinutes = new("30minutes", 30, "30 minutes");
    public static readonly LiveFolderRefreshInterval OneHour = new("1hour", 60, "1 hour");
    public static readonly LiveFolderRefreshInterval TwoHours = new("2hours", 120, "2 hours");
    public static readonly LiveFolderRefreshInterval FourHours = new("4hours", 240, "4 hours");
    public static readonly LiveFolderRefreshInterval EightHours = new("8hours", 480, "8 hours");
    public static IReadOnlyList<LiveFolderRefreshInterval> All { get; } =
        [FifteenMinutes, ThirtyMinutes, OneHour, TwoHours, FourHours, EightHours];

    #endregion

    #region Variables

    public string Name { get; }
    public int Minutes { get; }
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private LiveFolderRefreshInterval(string name, int minutes, string title) {
        Name = name;
        Minutes = minutes;
        Title = title;
    }

    #endregion

    #region Actions - Reading

    public static LiveFolderRefreshInterval? Named(string? name) => All.FirstOrDefault(interval => interval.Name == name);

    #endregion
}
