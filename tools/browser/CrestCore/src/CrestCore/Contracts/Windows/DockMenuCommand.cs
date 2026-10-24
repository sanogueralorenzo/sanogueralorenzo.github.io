namespace CrestCore.Contracts;

/// A window command the Dock icon's menu offers above the Spaces. Each one
/// opens a window of its own kind, which is what a person reaches for in the
/// Dock while Crest is in the background, and runs the shortcut command the
/// menu bar runs for the same choice. `All` is the order the menu lists them,
/// the File menu's order, and it only grows at the end.
public sealed class DockMenuCommand {
    #region Static Variables

    public static readonly DockMenuCommand NewWindow = new(name: "newWindow", ShortcutCommand.NewWindow, title: "New Window");
    public static readonly DockMenuCommand NewQuickWindow = new(name: "newQuickWindow", ShortcutCommand.NewQuickWindow,
        title: "New Quick Window");
    public static readonly DockMenuCommand NewPrivateWindow = new(name: "newPrivateWindow", ShortcutCommand.NewPrivateWindow,
        title: "New Private Window");

    public static IReadOnlyList<DockMenuCommand> All { get; } = [NewWindow, NewQuickWindow, NewPrivateWindow];

    #endregion

    #region Variables

    public string Name { get; }

    /// The shortcut command a platform runs for this choice, as its menu bar
    /// does.
    public ShortcutCommand Command { get; }

    /// What the Dock menu calls the command.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private DockMenuCommand(string name, ShortcutCommand command, string title) {
        Name = name;
        Command = command;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static DockMenuCommand? Named(string? name) => All.FirstOrDefault(command => command.Name == name);

    #endregion
}
