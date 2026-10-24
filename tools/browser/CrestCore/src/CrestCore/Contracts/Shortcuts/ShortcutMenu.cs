namespace CrestCore.Contracts;

/// A menu of the menu bar that holds Crest's commands: its title and its
/// commands in groups, first to last, which a platform separates. Every
/// command sits in exactly one group, so each has a menu item, and a platform
/// whose shortcuts run through its menus runs every chord. Menus are listed in
/// the order the menu bar shows them; a platform adds its own standard menus
/// and items around them, such as the application menu, text editing, window
/// management and help. `All` is append-only.
public sealed class ShortcutMenu {
    #region Static Variables

    public static readonly ShortcutMenu File = new(name: "file", title: "File", groups: [
        [ShortcutCommand.NewWindow, ShortcutCommand.NewBlankWindow, ShortcutCommand.NewTab, ShortcutCommand.NewQuickWindow,
            ShortcutCommand.NewPrivateWindow],
        [ShortcutCommand.OpenFile],
        [ShortcutCommand.CloseTabOrWindow, ShortcutCommand.CloseWindow],
        [ShortcutCommand.PrintPage]
    ]);
    public static readonly ShortcutMenu View = new(name: "view", title: "View", groups: [
        [ShortcutCommand.ToggleSidebar, ShortcutCommand.ToggleTranslationToolbar],
        [ShortcutCommand.ShowHistory, ShortcutCommand.ShowArchive, ShortcutCommand.ShowDownloads]
    ]);
    public static readonly ShortcutMenu Navigate = new(name: "navigate", title: "Navigate", groups: [
        [ShortcutCommand.OpenLocation],
        [ShortcutCommand.Back, ShortcutCommand.Forward, ShortcutCommand.ReloadPage, ShortcutCommand.StopLoading,
            ShortcutCommand.ReloadFromOrigin]
    ]);
    public static readonly ShortcutMenu Tabs = new(name: "tabs", title: "Tabs", groups: [
        [ShortcutCommand.ToggleSelectedTabPinned, ShortcutCommand.DuplicateTab, ShortcutCommand.ReopenClosedTab,
            ShortcutCommand.ClearUnpinnedTabs, ShortcutCommand.ArchiveTab],
        [ShortcutCommand.PreviousTab, ShortcutCommand.NextTab, ShortcutCommand.MostRecentTab],
        [ShortcutCommand.SplitWithNextTab, ShortcutCommand.FocusNextSplitCard, ShortcutCommand.FocusPreviousSplitCard,
            ShortcutCommand.MoveSplitCardLeft, ShortcutCommand.MoveSplitCardRight, ShortcutCommand.RemoveTabFromSplit,
            ShortcutCommand.SeparateSplitTabs],
        Numbered(NumberedSelectionTarget.Tab)
    ]);
    public static readonly ShortcutMenu Spaces = new(name: "spaces", title: "Spaces", groups: [
        [ShortcutCommand.PreviousSpace, ShortcutCommand.NextSpace],
        Numbered(NumberedSelectionTarget.Space)
    ]);
    public static readonly ShortcutMenu Page = new(name: "page", title: "Page", groups: [
        [ShortcutCommand.ToggleReaderMode, ShortcutCommand.ToggleContentBlocking],
        [ShortcutCommand.FindInPage, ShortcutCommand.FindNext, ShortcutCommand.FindPrevious],
        [ShortcutCommand.ZoomIn, ShortcutCommand.ZoomOut, ShortcutCommand.ActualSize],
        [ShortcutCommand.CopyPageLink, ShortcutCommand.CopyPageLinkAsMarkdown, ShortcutCommand.SharePage, ShortcutCommand.ExportPDF,
            ShortcutCommand.SaveWebArchive, ShortcutCommand.CapturePage]
    ]);
    public static readonly ShortcutMenu Develop = new(name: "develop", title: "Develop", groups: [
        [ShortcutCommand.ToggleDeveloperToolbar],
        [ShortcutCommand.ShowWebInspector]
    ]);

    public static IReadOnlyList<ShortcutMenu> All { get; } = [File, View, Navigate, Tabs, Spaces, Page, Develop];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the menu bar calls the menu.
    [Localized]
    public string Title { get; }

    /// The menu's commands in groups, first to last. A platform separates the
    /// groups and leaves out what the device does not offer.
    public IReadOnlyList<IReadOnlyList<ShortcutCommand>> Groups { get; }

    #endregion

    #region Constructors

    private ShortcutMenu(string name, string title, IReadOnlyList<IReadOnlyList<ShortcutCommand>> groups) {
        Name = name;
        Title = title;
        Groups = groups;
    }

    #endregion

    #region Actions - Lookup

    public static ShortcutMenu? Named(string? name) => All.FirstOrDefault(menu => menu.Name == name);

    /// The numbered commands that select from `target`, in order.
    private static IReadOnlyList<ShortcutCommand> Numbered(NumberedSelectionTarget target) =>
        [.. ShortcutCommand.All.Where(command => command.Selects == target)];

    #endregion
}
