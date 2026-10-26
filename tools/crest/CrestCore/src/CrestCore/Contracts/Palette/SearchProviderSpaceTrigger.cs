namespace CrestCore.Contracts;

/// How Space after a provider shortcut enters its search. Stored names stay stable;
/// the generated wire tag follows this append-only order.
public sealed class SearchProviderSpaceTrigger {
    #region Static Variables

    public static readonly SearchProviderSpaceTrigger Off = new("off", "Off", "A space after a provider’s shortcut stays a space.", false, false);
    public static readonly SearchProviderSpaceTrigger PrefixedShortcut = new("prefixedShortcut", "After $ and a shortcut",
        "Type $yt and a space to search YouTube.", true, true);
    public static readonly SearchProviderSpaceTrigger Shortcut = new("shortcut", "After a shortcut",
        "Type yt or $yt and a space to search YouTube.", true, false);
    public static IReadOnlyList<SearchProviderSpaceTrigger> All { get; } = [Off, PrefixedShortcut, Shortcut];

    #endregion

    #region Variables

    /// The stored name, which never changes.
    public string Name { get; }
    /// The choice as Settings lists it.
    [Localized]
    public string Title { get; }
    /// What a person types for it, shown under the choice.
    [Localized]
    public string Example { get; }
    /// Whether Space enters a provider at all.
    public bool IsEnabled { get; }
    /// Whether the shortcut needs the provider sign before it.
    public bool RequiresPrefix { get; }

    #endregion

    #region Constructors

    private SearchProviderSpaceTrigger(string name, string title, string example, bool isEnabled, bool requiresPrefix) {
        Name = name;
        Title = title;
        Example = example;
        IsEnabled = isEnabled;
        RequiresPrefix = requiresPrefix;
    }

    #endregion

    #region Actions - Triggers

    /// The shortcut the word names, or null when this mode does not accept it.
    public string? ShortcutFrom(string word, char sign) {
        if (!IsEnabled) return null;
        if (word.StartsWith(sign)) return word.Length > 1 ? word[1..] : null;
        return RequiresPrefix ? null : word;
    }

    public static SearchProviderSpaceTrigger? Named(string? name) => All.FirstOrDefault(mode => mode.Name == name);

    #endregion
}
