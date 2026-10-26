namespace CrestCore.Contracts;

/// A narrowing of the palette to one kind of result, entered by typing its
/// `Keyword` and pressing Tab: it then lists every match of that kind, and
/// nothing else, until the person leaves it. A scope travels as its index in
/// `All`, so `All` is append-only.
public sealed class PaletteScope {
    #region Static Variables

    public static readonly PaletteScope Tabs = new(name: "tabs", keyword: "@tabs", title: "Tabs", symbol: "square.on.square",
        source: PaletteSource.OpenTabs);
    public static readonly PaletteScope Saved = new(name: "saved", keyword: "@saved", title: "Pinned & Saved", symbol: "pin",
        source: PaletteSource.Saved);
    public static readonly PaletteScope History = new(name: "history", keyword: "@history", title: "History", symbol: "clock",
        source: PaletteSource.History);
    public static readonly PaletteScope Actions = new(name: "actions", keyword: "@actions", title: "Actions", symbol: "command",
        source: PaletteSource.Actions);
    public static readonly PaletteScope Spaces = new(name: "spaces", keyword: "@spaces", title: "Spaces", symbol: "square.stack",
        source: PaletteSource.Spaces);

    public static IReadOnlyList<PaletteScope> All { get; } = [Tabs, Saved, History, Actions, Spaces];

    #endregion

    #region Variables

    public string Name { get; }

    /// What a person types before Tab to enter the scope.
    public string Keyword { get; }

    /// What the scope's chip says.
    [Localized]
    public string Title { get; }

    /// The SF Symbol the scope's chip wears.
    public string Symbol { get; }

    /// The only kind of result the scope offers.
    public PaletteSource Source { get; }

    #endregion

    #region Constructors

    private PaletteScope(string name, string keyword, string title, string symbol, PaletteSource source) {
        Name = name;
        Keyword = keyword;
        Title = title;
        Symbol = symbol;
        Source = source;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteScope? Named(string? name) => All.FirstOrDefault(scope => scope.Name == name);

    /// The scope whose keyword is `word`, ignoring case, or null.
    public static PaletteScope? Keyed(string word) =>
        All.FirstOrDefault(scope => string.Equals(scope.Keyword, word, StringComparison.OrdinalIgnoreCase));

    #endregion
}
