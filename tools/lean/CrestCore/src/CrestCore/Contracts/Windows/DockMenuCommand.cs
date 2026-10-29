namespace CrestCore.Contracts;

/// A window command the Dock icon's menu offers above the Spaces. Each one
/// opens a window of its own kind, which is what a person reaches for in the
/// Dock while Crest is in the background, and runs the shortcut command the
/// menu bar runs for the same choice. `All` is the order the menu lists them,
/// the File menu's order, and it only grows at the end.
public sealed class DockMenuCommand {
    #region Static Variables

    public static readonly DockMenuCommand NewWindow = new(name: "newWindow", title: "New Window");
    public static readonly DockMenuCommand NewPrivateWindow = new(name: "newPrivateWindow", title: "New Private Window");

    public static IReadOnlyList<DockMenuCommand> All { get; } = [NewWindow, NewPrivateWindow];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the Dock menu calls the command.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private DockMenuCommand(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static DockMenuCommand? Named(string? name) => All.FirstOrDefault(command => command.Name == name);

    #endregion
}
