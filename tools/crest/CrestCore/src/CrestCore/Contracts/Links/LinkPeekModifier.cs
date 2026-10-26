namespace CrestCore.Contracts;

/// The key a person holds while clicking a link to open it in Peek. The other
/// of Option and Command then opens the link in a new tab.
///
/// Link preferences (`crest.link-preferences.v1`) and the link-navigation
/// policy spell a modifier as its `Name`, so a name never changes.
public sealed class LinkPeekModifier {
    #region Variables

    public static readonly LinkPeekModifier Option = new(name: "option", title: "Option (⌥)", clickTitle: "Option-click",
        peekKey: ShortcutModifiers.Option, newTabKey: ShortcutModifiers.Command);
    public static readonly LinkPeekModifier Command = new(name: "command", title: "Command (⌘)", clickTitle: "Command-click",
        peekKey: ShortcutModifiers.Command, newTabKey: ShortcutModifiers.Option);

    public static IReadOnlyList<LinkPeekModifier> All { get; } = [Option, Command];

    public string Name { get; }

    /// What the link settings call the modifier.
    [Localized]
    public string Title { get; }

    /// The click the link settings' guidance names.
    [Localized]
    public string ClickTitle { get; }

    /// The key that opens a clicked link in Peek.
    public ShortcutModifiers PeekKey { get; }

    /// The key that opens a clicked link in a new tab.
    public ShortcutModifiers NewTabKey { get; }

    #endregion

    #region Constructors

    private LinkPeekModifier(string name, string title, string clickTitle, ShortcutModifiers peekKey, ShortcutModifiers newTabKey) {
        Name = name;
        Title = title;
        ClickTitle = clickTitle;
        PeekKey = peekKey;
        NewTabKey = newTabKey;
    }

    #endregion

    #region Actions - Lookup

    public static LinkPeekModifier? Named(string? name) => All.FirstOrDefault(modifier => modifier.Name == name);

    #endregion

    #region Actions - Clicks

    /// What a click with `held` keys asks for. Peek wins over the new-tab key
    /// when both are held, and a middle click always asks for a new tab.
    public (bool Peek, bool NewTab) Intent(ShortcutModifiers held, bool isMiddleClick) {
        bool peek = held.HasFlag(PeekKey);
        return (peek, (!peek && held.HasFlag(NewTabKey)) || isMiddleClick);
    }

    #endregion
}
