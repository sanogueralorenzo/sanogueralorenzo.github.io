namespace CrestCore.Contracts;

/// Native modifier bits carried by a page link gesture.
[Flags]
public enum ShortcutModifiers {
    None = 0,
    Command = 1 << 0,
    Option = 1 << 1,
    Control = 1 << 2,
    Shift = 1 << 3
}
