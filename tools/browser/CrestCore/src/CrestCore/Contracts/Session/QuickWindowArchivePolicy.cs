namespace CrestCore.Contracts;

/// How long an inactive Quick Window stays open before it archives itself.
///
/// The link preferences spell a choice as its `Name`, so a name never changes.
/// A choice travels as its index in `All`, so `All` is append-only.
public sealed class QuickWindowArchivePolicy {
    #region Variables

    public static readonly QuickWindowArchivePolicy After1Hour = new(name: "after1Hour", title: "After 1 Hour",
        lifetime: TimeSpan.FromHours(1));
    public static readonly QuickWindowArchivePolicy After6Hours = new(name: "after6Hours", title: "After 6 Hours",
        lifetime: TimeSpan.FromHours(6));
    public static readonly QuickWindowArchivePolicy After12Hours = new(name: "after12Hours", title: "After 12 Hours",
        lifetime: TimeSpan.FromHours(12));
    public static readonly QuickWindowArchivePolicy After24Hours = new(name: "after24Hours", title: "After 24 Hours",
        lifetime: TimeSpan.FromHours(24));
    public static readonly QuickWindowArchivePolicy Never = new(name: "never", title: "Never", lifetime: null);

    /// The choices, in the order the settings offer them.
    public static IReadOnlyList<QuickWindowArchivePolicy> All { get; } = [After1Hour, After6Hours, After12Hours, After24Hours, Never];

    public string Name { get; }

    /// What the settings call the choice.
    [Localized]
    public string Title { get; }

    /// How long the window may stay inactive; null never archives it.
    public TimeSpan? Lifetime { get; }

    #endregion

    #region Constructors

    private QuickWindowArchivePolicy(string name, string title, TimeSpan? lifetime) {
        Name = name;
        Title = title;
        Lifetime = lifetime;
    }

    #endregion

    #region Actions - Lookup

    public static QuickWindowArchivePolicy? Named(string? name) => All.FirstOrDefault(policy => policy.Name == name);

    #endregion
}
