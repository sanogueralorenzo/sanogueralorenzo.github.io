namespace CrestCore.Contracts;

#region Queries

/// Each numbered command that reaches something, in catalog order.
public sealed record NumberedSelectionList(IReadOnlyList<NumberedSelection> Selections);

#endregion

#region Changes

/// The fixed keys each offered command answers to, in catalog order.
public sealed record ShortcutsChanged(IReadOnlyList<ShortcutBinding> Bindings) : Change;

/// The keys one command answers to, or null when it has none.
public sealed record ShortcutBinding(ShortcutCommand Command, KeyCombination? Keys);

#endregion

#region Rejections

/// Native keys that cannot form a supported shortcut chord.
public sealed record InvalidShortcut(KeyCombination Keys) : Rejection;

#endregion

#region Models

/// A key and the modifiers held with it, as the shortcut catalog writes a
/// default. `Key` is the character the key types, or a special key's native
/// spelling, such as `leftArrow`, when `IsSpecialKey`.
public sealed record KeyCombination(string Key, bool IsSpecialKey, ShortcutModifiers Modifiers);

/// What a window's numbered commands choose from: the Space it shows, the tab
/// each stop of that Space's sidebar leads to, in order, and the Spaces it may
/// show, in order.
public sealed record NumberedChoices(Guid ShownSpaceId, IReadOnlyList<Guid> Tabs, IReadOnlyList<Guid> Spaces);

/// A numbered command, what it selects from, and where it leads: the Space
/// `SpaceId`, and for a tab the tab `TabId` the window shows there.
public sealed record NumberedSelection(ShortcutCommand Command, NumberedSelectionTarget Target, Guid SpaceId, Guid? TabId);

/// A command's fixed key combination on one platform.
public sealed record ShortcutDefault(DevicePlatform Platform, KeyCombination Keys);

/// The modifier keys held with a shortcut's key. The values are the bits of
/// the native modifier mask that persisted shortcuts store.
[Flags]
public enum ShortcutModifiers {
    None = 0,
    Command = 1 << 0,
    Option = 1 << 1,
    Control = 1 << 2,
    Shift = 1 << 3
}

/// What a window shows, as the commands that act on it read it: whether it
/// shows a Space, in a private workspace or not, the tab it shows there, and
/// what that Space and tab allow. Commands carry their own rule over these
/// facts; see `ShortcutCommand.IsAvailable`.
public sealed record WindowCommandFacts(bool ShowsSpace, bool IsPrivate, TabState? ShownTab, bool HasArchivedTabs,
    bool HasSplitCandidate, int CardCount);

#endregion
