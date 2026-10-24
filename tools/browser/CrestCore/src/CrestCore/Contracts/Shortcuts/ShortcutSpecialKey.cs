using System.Globalization;

namespace CrestCore.Contracts;

/// A key a shortcut can use that types no character, with how a shortcut list
/// shows it and how assistive technology reads it.
///
/// The device store and the shortcut choices earlier releases kept spell a key
/// as its `Name`, so a name never changes. `All` is append-only.
public sealed class ShortcutSpecialKey {
    #region Variables

    public static readonly ShortcutSpecialKey Tab = new(name: "tab", glyph: "⇥", spokenName: "tab");
    public static readonly ShortcutSpecialKey LeftArrow = new(name: "leftArrow", glyph: "←", spokenName: "left arrow");
    public static readonly ShortcutSpecialKey RightArrow = new(name: "rightArrow", glyph: "→", spokenName: "right arrow");
    public static readonly ShortcutSpecialKey UpArrow = new(name: "upArrow", glyph: "↑", spokenName: "up arrow");
    public static readonly ShortcutSpecialKey DownArrow = new(name: "downArrow", glyph: "↓", spokenName: "down arrow");
    public static readonly ShortcutSpecialKey Escape = new(name: "escape", glyph: "⎋", spokenName: "escape");
    public static readonly ShortcutSpecialKey ReturnKey = new(name: "returnKey", glyph: "↩", spokenName: "return");
    public static readonly ShortcutSpecialKey Delete = new(name: "delete", glyph: "⌫", spokenName: "delete");
    public static readonly ShortcutSpecialKey ForwardDelete = new(name: "forwardDelete", glyph: "⌦", spokenName: "forward delete");
    public static readonly ShortcutSpecialKey Home = new(name: "home", glyph: "↖", spokenName: "home");
    public static readonly ShortcutSpecialKey End = new(name: "end", glyph: "↘", spokenName: "end");
    public static readonly ShortcutSpecialKey PageUp = new(name: "pageUp", glyph: "⇞", spokenName: "page up");
    public static readonly ShortcutSpecialKey PageDown = new(name: "pageDown", glyph: "⇟", spokenName: "page down");
    // The space bar has no glyph, so a list names it.
    public static readonly ShortcutSpecialKey Space = new(name: "space", glyph: null, spokenName: "space", title: "Space");
    public static readonly ShortcutSpecialKey F1 = FunctionKey(1);
    public static readonly ShortcutSpecialKey F2 = FunctionKey(2);
    public static readonly ShortcutSpecialKey F3 = FunctionKey(3);
    public static readonly ShortcutSpecialKey F4 = FunctionKey(4);
    public static readonly ShortcutSpecialKey F5 = FunctionKey(5);
    public static readonly ShortcutSpecialKey F6 = FunctionKey(6);
    public static readonly ShortcutSpecialKey F7 = FunctionKey(7);
    public static readonly ShortcutSpecialKey F8 = FunctionKey(8);
    public static readonly ShortcutSpecialKey F9 = FunctionKey(9);
    public static readonly ShortcutSpecialKey F10 = FunctionKey(10);
    public static readonly ShortcutSpecialKey F11 = FunctionKey(11);
    public static readonly ShortcutSpecialKey F12 = FunctionKey(12);
    public static readonly ShortcutSpecialKey F13 = FunctionKey(13);
    public static readonly ShortcutSpecialKey F14 = FunctionKey(14);
    public static readonly ShortcutSpecialKey F15 = FunctionKey(15);
    public static readonly ShortcutSpecialKey F16 = FunctionKey(16);
    public static readonly ShortcutSpecialKey F17 = FunctionKey(17);
    public static readonly ShortcutSpecialKey F18 = FunctionKey(18);
    public static readonly ShortcutSpecialKey F19 = FunctionKey(19);
    public static readonly ShortcutSpecialKey F20 = FunctionKey(20);

    public static IReadOnlyList<ShortcutSpecialKey> All { get; } = [
        Tab, LeftArrow, RightArrow, UpArrow, DownArrow, Escape, ReturnKey, Delete, ForwardDelete, Home, End, PageUp, PageDown,
        Space, F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20
    ];

    public string Name { get; }

    /// How a shortcut list shows the key, when a glyph stands for it.
    public string? Glyph { get; }

    /// How a shortcut list names a key that has no glyph.
    [Localized]
    public string? Title { get; }

    /// How assistive technology reads the key. A function key is read by its
    /// name.
    [Localized]
    public string? SpokenName { get; }

    /// A function key's number, counting from one.
    public int? FunctionKeyNumber { get; }

    #endregion

    #region Constructors

    private ShortcutSpecialKey(string name, string? glyph, string? spokenName, string? title = null, int? functionKeyNumber = null) {
        Name = name;
        Glyph = glyph;
        Title = title;
        SpokenName = spokenName;
        FunctionKeyNumber = functionKeyNumber;
    }

    private static ShortcutSpecialKey FunctionKey(int number) {
        string digits = number.ToString(CultureInfo.InvariantCulture);
        return new(name: "f" + digits, glyph: "F" + digits, spokenName: null, functionKeyNumber: number);
    }

    #endregion

    #region Actions - Lookup

    public static ShortcutSpecialKey? Named(string? name) => All.FirstOrDefault(key => key.Name == name);

    #endregion
}
