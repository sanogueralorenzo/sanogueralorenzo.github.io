namespace CrestCore.Contracts;

#region Queries

/// Each numbered command that reaches something, in catalog order.
public sealed record NumberedSelectionList(IReadOnlyList<NumberedSelection> Selections);

#endregion

#region Changes

/// The chord each offered command answers to changed. `Bindings` covers every
/// offered command in catalog order; `IsCustomized` says whether the person
/// changed any shortcut, including one this device does not offer.
public sealed record ShortcutsChanged(IReadOnlyList<ShortcutBinding> Bindings, bool IsCustomized) : Change;

/// The keys one command answers to now, or null when it has none, and whether
/// they are the person's choice rather than the default.
public sealed record ShortcutBinding(ShortcutCommand Command, KeyCombination? Keys, bool IsCustomized);

#endregion

#region Rejections

/// The keys can never be a shortcut: they hold no supported modifier, so a
/// plain key would never reach the focused text field, or they name no key.
public sealed record InvalidShortcut(KeyCombination Keys) : Rejection;

/// Other offered commands answer to the keys already.
public sealed record ShortcutInUse(IReadOnlyList<ShortcutCommand> Commands) : Rejection;

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

/// A command's default key combination on one platform. A default that
/// `YieldsToOverrides` stays unbound while the person has given its keys to
/// another command, so a default added after people could customize never
/// takes keys they already chose; resetting that command restores it.
public sealed record ShortcutDefault(DevicePlatform Platform, KeyCombination Keys, bool YieldsToOverrides);

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
