namespace CrestCore.Contracts;

/// The group a shortcut command sits in on the shortcut settings list and in
/// the launcher. Sections are listed in `All` order.
public sealed class ShortcutSection {
    #region Variables

    public static readonly ShortcutSection Everyday = new(name: "everyday", title: "Everyday Use");
    public static readonly ShortcutSection Tabs = new(name: "tabs", title: "Tabs");
    public static readonly ShortcutSection Spaces = new(name: "spaces", title: "Spaces");
    public static readonly ShortcutSection Page = new(name: "page", title: "Page");
    public static readonly ShortcutSection View = new(name: "view", title: "View & Tools");

    public static IReadOnlyList<ShortcutSection> All { get; } = [Everyday, Tabs, Spaces, Page, View];

    public string Name { get; }

    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private ShortcutSection(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static ShortcutSection? Named(string? name) => All.FirstOrDefault(section => section.Name == name);

    #endregion
}
