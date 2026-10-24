using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// One key chord: a typed character or a named special key, and a modifier
/// mask. The mask keeps every bit the platform stored so equality matches the
/// native value exactly; only the four supported bits make a chord usable.
public sealed record ShortcutChord {
    #region Variables

    public const int Command = (int)ShortcutModifiers.Command;
    public const int Option = (int)ShortcutModifiers.Option;
    public const int Control = (int)ShortcutModifiers.Control;
    public const int Shift = (int)ShortcutModifiers.Shift;
    public const int SupportedModifiers = Command | Option | Control | Shift;
    public const int MaximumCharacterLength = 64;

    public string Key { get; }
    public bool IsSpecial { get; }
    public int Modifiers { get; }

    /// A chord needs at least one supported modifier, so a plain key keeps
    /// reaching the focused text field.
    public bool IsValid => (Modifiers & SupportedModifiers) != 0;

    /// The chord as the platform reads it.
    public KeyCombination Keys => new(Key, IsSpecial, (ShortcutModifiers)Modifiers);

    #endregion

    #region Constructors

    private ShortcutChord(string key, bool isSpecial, int modifiers) {
        Key = key;
        IsSpecial = isSpecial;
        Modifiers = modifiers;
    }

    #endregion

    #region Actions - Construction

    /// A typed character, compared in canonical composition so the two
    /// spellings of an accented key are one chord. Refused with
    /// `InvalidShortcut` for an empty or overlong character.
    public static ShortcutChord Character(string character, int modifiers) {
        ArgumentNullException.ThrowIfNull(character);
        if (character.Length == 0 || character.Length > MaximumCharacterLength)
            throw new Rejected(new InvalidShortcut(new(character, false, (ShortcutModifiers)modifiers)));
        return new(character.Normalize(NormalizationForm.FormC), false, modifiers);
    }

    /// The chord `keys` spell when a person may bind it: a character of usable
    /// length or a special key this build knows, held with at least one
    /// supported modifier. Null for keys that can never be a shortcut.
    public static ShortcutChord? Usable(KeyCombination keys) {
        ArgumentNullException.ThrowIfNull(keys);
        if (keys.IsSpecialKey ? ShortcutSpecialKey.Named(keys.Key) is null : keys.Key.Length is 0 or > MaximumCharacterLength) return null;
        var chord = Of(keys);
        return chord.IsValid ? chord : null;
    }

    /// The chord a catalog default names.
    public static ShortcutChord Of(KeyCombination keys) {
        ArgumentNullException.ThrowIfNull(keys);
        return keys.IsSpecialKey ? Special(keys.Key, (int)keys.Modifiers) : Character(keys.Key, (int)keys.Modifiers);
    }

    /// A named special key. Refused with `InvalidShortcut` for a key this
    /// build does not know.
    public static ShortcutChord Special(string key, int modifiers) {
        ArgumentNullException.ThrowIfNull(key);
        if (ShortcutSpecialKey.Named(key) is null) throw new Rejected(new InvalidShortcut(new(key, true, (ShortcutModifiers)modifiers)));
        return new(key, true, modifiers);
    }

    #endregion
}
