namespace CrestCore.Contracts;

/// How long an open tab nobody uses stays before cleanup archives it.
///
/// The stored session spells a choice as its `Name`, so a name never changes.
/// A choice travels as its index in `All`, so `All` is append-only.
public sealed class CurrentTabCleanup {
    #region Variables

    public static readonly CurrentTabCleanup After12Hours = new(name: "after12Hours", title: "After 12 Hours",
        lifetime: TimeSpan.FromHours(12));
    public static readonly CurrentTabCleanup After24Hours = new(name: "after24Hours", title: "After 24 Hours",
        lifetime: TimeSpan.FromDays(1));
    public static readonly CurrentTabCleanup After7Days = new(name: "after7Days", title: "After 7 Days", lifetime: TimeSpan.FromDays(7));
    public static readonly CurrentTabCleanup After30Days = new(name: "after30Days", title: "After 30 Days",
        lifetime: TimeSpan.FromDays(30));
    public static readonly CurrentTabCleanup Never = new(name: "never", title: "Never", lifetime: null);

    /// The choices, in the order the settings offer them.
    public static IReadOnlyList<CurrentTabCleanup> All { get; } = [After12Hours, After24Hours, After7Days, After30Days, Never];

    public string Name { get; }

    /// What the settings call the choice.
    [Localized]
    public string Title { get; }

    /// How long an open tab may go unused; null keeps it.
    public TimeSpan? Lifetime { get; }

    #endregion

    #region Constructors

    private CurrentTabCleanup(string name, string title, TimeSpan? lifetime) {
        Name = name;
        Title = title;
        Lifetime = lifetime;
    }

    #endregion

    #region Actions - Lookup

    public static CurrentTabCleanup? Named(string? name) => All.FirstOrDefault(cleanup => cleanup.Name == name);

    #endregion
}
