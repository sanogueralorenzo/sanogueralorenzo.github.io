namespace CrestCore.Domain;

/// Where a palette row leads, as the palette remembers a pick: a page by its
/// place key, which the same site's open tab, saved tab and history share, or
/// a folder, command, Space, settings page or scope by name.
public sealed record PaletteDestination(PaletteDestinationKind Kind, string Value) {
    #region Actions - Making

    /// The page at `url`, or null for an address the palette does not remember.
    public static PaletteDestination? Address(string? url) =>
        url is not null && PaletteMemory.Place(url) is { } place ? new(PaletteDestinationKind.Address, place) : null;

    /// The thing of `kind` named `value`.
    public static PaletteDestination Named(PaletteDestinationKind kind, string value) => new(kind, value);

    #endregion
}

/// What kind of thing a remembered pick leads to. The device store spells a
/// kind as its `Name`, so a name never changes.
public sealed class PaletteDestinationKind {
    #region Static Variables

    public static readonly PaletteDestinationKind Address = new(name: "address");
    public static readonly PaletteDestinationKind Folder = new(name: "folder");
    public static readonly PaletteDestinationKind Command = new(name: "command");
    public static readonly PaletteDestinationKind Space = new(name: "space");
    public static readonly PaletteDestinationKind SettingsPage = new(name: "settingsPage");
    public static readonly PaletteDestinationKind Scope = new(name: "scope");

    public static IReadOnlyList<PaletteDestinationKind> All { get; } = [Address, Folder, Command, Space, SettingsPage, Scope];

    #endregion

    #region Variables

    public string Name { get; }

    #endregion

    #region Constructors

    private PaletteDestinationKind(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static PaletteDestinationKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
