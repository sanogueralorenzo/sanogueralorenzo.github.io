using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What a palette row is and does: what activating it does, the symbol it
/// wears unless the row names its own, the words that say so at its end, the
/// word the blended layout shows for its kind, whether it is one of the
/// palette's primary actions, which show larger, whether forgetting it leaves
/// history too, and where it leads as the palette remembers a pick. A kind travels as its index in `All`, so `All`
/// is append-only.
public sealed class PaletteRowKind {
    #region Static Variables

    public static readonly PaletteRowKind OpenAddress = new(name: "openAddress", PaletteActivation.OpensAddress,
        symbol: "globe", action: null, label: "Website", isPrimary: true, forgetsFromHistory: false,
        destination: (row, _) => PaletteDestination.Address(row.Address));
    public static readonly PaletteRowKind Search = new(name: "search", PaletteActivation.Searches,
        symbol: "magnifyingglass", action: null, label: "Search", isPrimary: true, forgetsFromHistory: false,
        destination: (_, _) => null);
    public static readonly PaletteRowKind SearchSuggestion = new(name: "searchSuggestion", PaletteActivation.Searches,
        symbol: "magnifyingglass", action: "Search", label: "Suggestion", isPrimary: false, forgetsFromHistory: false,
        destination: (_, _) => null);
    public static readonly PaletteRowKind Tab = new(name: "tab", PaletteActivation.SwitchesToTab,
        symbol: "globe", action: "Switch to Tab", label: "Open Tab", isPrimary: false, forgetsFromHistory: false,
        destination: (row, tabs) => PaletteDestination.Address(row.TabId is { } tab ? tabs(tab) : null));
    public static readonly PaletteRowKind PinnedTab = new(name: "pinnedTab", PaletteActivation.SwitchesToTab,
        symbol: "pin.fill", action: "Switch to Tab", label: "Pinned", isPrimary: false, forgetsFromHistory: false,
        destination: (row, tabs) => PaletteDestination.Address(row.TabId is { } tab ? tabs(tab) : null));
    public static readonly PaletteRowKind SavedTab = new(name: "savedTab", PaletteActivation.SwitchesToTab,
        symbol: "bookmark", action: "Switch to Tab", label: "Saved", isPrimary: false, forgetsFromHistory: false,
        destination: (row, tabs) => PaletteDestination.Address(row.TabId is { } tab ? tabs(tab) : null));
    public static readonly PaletteRowKind Folder = new(name: "folder", PaletteActivation.SwitchesToTab,
        symbol: FolderState.DefaultSymbol, action: "Open First Tab", label: "Folder", isPrimary: false, forgetsFromHistory: false,
        destination: (row, _) => row.SubjectId is { } folder
            ? PaletteDestination.Named(PaletteDestinationKind.Folder, folder.ToString("D")) : null);
    public static readonly PaletteRowKind Command = new(name: "command", PaletteActivation.RunsCommand,
        symbol: "command", action: null, label: "Action", isPrimary: false, forgetsFromHistory: false,
        destination: (row, _) => row.Command is { } command
            ? PaletteDestination.Named(PaletteDestinationKind.Command, command.Name) : null);
    public static readonly PaletteRowKind History = new(name: "history", PaletteActivation.OpensAddress,
        symbol: "clock", action: "Open", label: "History", isPrimary: false, forgetsFromHistory: true,
        destination: (row, _) => PaletteDestination.Address(row.Address));
    public static readonly PaletteRowKind Space = new(name: "space", PaletteActivation.ShowsSpace,
        symbol: "square.stack", action: "Switch to Space", label: "Space", isPrimary: false, forgetsFromHistory: false,
        destination: (row, _) => row.SubjectId is { } space
            ? PaletteDestination.Named(PaletteDestinationKind.Space, space.ToString("D")) : null);
    public static readonly PaletteRowKind ArchivedTab = new(name: "archivedTab", PaletteActivation.ReopensArchivedTab,
        symbol: "archivebox", action: "Reopen", label: "Archived", isPrimary: false, forgetsFromHistory: false,
        destination: (_, _) => null);
    public static readonly PaletteRowKind SettingsPage = new(name: "settingsPage", PaletteActivation.OpensSettingsPage,
        symbol: "gearshape", action: "Open Settings", label: "Settings", isPrimary: false, forgetsFromHistory: false,
        destination: (row, _) => row.SettingsPage is { } page ? PaletteDestination.Named(PaletteDestinationKind.SettingsPage, page) : null);
    public static readonly PaletteRowKind Calculation = new(name: "calculation", PaletteActivation.CopiesAnswer,
        symbol: "equal", action: "Copy", label: "Calculator", isPrimary: true, forgetsFromHistory: false,
        destination: (_, _) => null);
    public static readonly PaletteRowKind PasteAndGo = new(name: "pasteAndGo", PaletteActivation.OpensAddress,
        symbol: "doc.on.clipboard", action: null, label: "Clipboard", isPrimary: true, forgetsFromHistory: false,
        destination: (row, _) => PaletteDestination.Address(row.Address));
    public static readonly PaletteRowKind Scope = new(name: "scope", PaletteActivation.EntersScope,
        symbol: "line.3.horizontal.decrease", action: "Search", label: "Scope", isPrimary: false, forgetsFromHistory: false,
        destination: (row, _) => row.Scope is { } scope ? PaletteDestination.Named(PaletteDestinationKind.Scope, scope.Name) : null);

    public static IReadOnlyList<PaletteRowKind> All { get; } =
        [OpenAddress, Search, SearchSuggestion, Tab, PinnedTab, SavedTab, Folder, Command, History, Space, ArchivedTab,
            SettingsPage, Calculation, PasteAndGo, Scope];

    #endregion

    #region Variables

    public string Name { get; }

    /// The SF Symbol a row of this kind wears unless it names its own.
    public string Symbol { get; }

    /// What activating the row does, shown at its end, or null for nothing.
    [Localized]
    public string? Action { get; }

    /// The kind as the blended layout names it at the row's end.
    [Localized]
    public string Label { get; }

    /// The row is one of the palette's primary actions.
    public bool IsPrimary { get; }

    /// What activating a row of this kind does.
    public PaletteActivation Activation { get; }

    /// Forgetting the row, as Shift-Delete does, removes its page from the
    /// Space's history as well as what the palette learned about it.
    public bool ForgetsFromHistory { get; }

    /// Where a row of this kind leads, as the palette remembers a pick, given
    /// how to read a tab's address; null for a row it never learns, such as a
    /// search.
    private readonly Func<PaletteRow, Func<Guid, string?>, PaletteDestination?> destination;

    #endregion

    #region Constructors

    private PaletteRowKind(string name, PaletteActivation activation, string symbol, string? action, string label, bool isPrimary,
        bool forgetsFromHistory, Func<PaletteRow, Func<Guid, string?>, PaletteDestination?> destination) {
        Name = name;
        Activation = activation;
        ForgetsFromHistory = forgetsFromHistory;
        Symbol = symbol;
        Action = action;
        Label = label;
        IsPrimary = isPrimary;
        this.destination = destination;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteRowKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion

    #region Actions - Learning

    /// Where `row`, of this kind, leads, reading a tab's address from `tabAddress`.
    internal PaletteDestination? Destination(PaletteRow row, Func<Guid, string?> tabAddress) => destination(row, tabAddress);

    #endregion
}
