using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What a palette row is and does: what activating it does, the symbol it
/// wears unless the row names its own, the words that say so at its end, whether it is one of the
/// palette's primary actions, which show larger, whether forgetting it leaves
/// history too. A kind travels as its index in `All`.
public sealed class PaletteRowKind {
    #region Static Variables

    public static readonly PaletteRowKind OpenAddress = new(name: "openAddress", PaletteActivation.OpensAddress,
        symbol: "globe", action: null, isPrimary: true, forgetsFromHistory: false);
    public static readonly PaletteRowKind Search = new(name: "search", PaletteActivation.Searches,
        symbol: "magnifyingglass", action: null, isPrimary: true, forgetsFromHistory: false);
    public static readonly PaletteRowKind SearchSuggestion = new(name: "searchSuggestion", PaletteActivation.Searches,
        symbol: "magnifyingglass", action: "Search", isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind Tab = new(name: "tab", PaletteActivation.SwitchesToTab,
        symbol: "globe", action: "Switch to Tab", isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind PinnedTab = new(name: "pinnedTab", PaletteActivation.SwitchesToTab,
        symbol: "pin.fill", action: "Switch to Tab", isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind SavedTab = new(name: "savedTab", PaletteActivation.SwitchesToTab,
        symbol: "bookmark", action: "Switch to Tab", isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind Folder = new(name: "folder", PaletteActivation.SwitchesToTab,
        symbol: FolderState.DefaultSymbol, action: "Open First Tab", isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind Command = new(name: "command", PaletteActivation.RunsCommand,
        symbol: "command", action: null, isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind History = new(name: "history", PaletteActivation.OpensAddress,
        symbol: "clock", action: "Open", isPrimary: false, forgetsFromHistory: true);
    public static readonly PaletteRowKind Space = new(name: "space", PaletteActivation.ShowsSpace,
        symbol: "square.stack", action: "Switch to Space", isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind SettingsPage = new(name: "settingsPage", PaletteActivation.OpensSettingsPage,
        symbol: "gearshape", action: "Open Settings", isPrimary: false, forgetsFromHistory: false);
    public static readonly PaletteRowKind Calculation = new(name: "calculation", PaletteActivation.CopiesAnswer,
        symbol: "equal", action: "Copy", isPrimary: true, forgetsFromHistory: false);
    public static readonly PaletteRowKind Scope = new(name: "scope", PaletteActivation.EntersScope,
        symbol: "line.3.horizontal.decrease", action: "Search", isPrimary: false, forgetsFromHistory: false);

    public static IReadOnlyList<PaletteRowKind> All { get; } =
        [OpenAddress, Search, SearchSuggestion, Tab, PinnedTab, SavedTab, Folder, Command, History, Space,
            SettingsPage, Calculation, Scope];

    #endregion

    #region Variables

    public string Name { get; }

    /// The SF Symbol a row of this kind wears unless it names its own.
    public string Symbol { get; }

    /// What activating the row does, shown at its end, or null for nothing.
    [Localized]
    public string? Action { get; }

    /// The row is one of the palette's primary actions.
    public bool IsPrimary { get; }

    /// What activating a row of this kind does.
    public PaletteActivation Activation { get; }

    /// Forgetting the row, as Shift-Delete does, removes its page from the
    /// Space's history.
    public bool ForgetsFromHistory { get; }

    #endregion

    #region Constructors

    private PaletteRowKind(string name, PaletteActivation activation, string symbol, string? action, bool isPrimary,
        bool forgetsFromHistory) {
        Name = name;
        Activation = activation;
        ForgetsFromHistory = forgetsFromHistory;
        Symbol = symbol;
        Action = action;
        IsPrimary = isPrimary;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteRowKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion

}
