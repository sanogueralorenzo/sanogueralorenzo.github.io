using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The person's shortcut choices on this device: for each command's stored
/// name, the chord they gave it, or null when they left it without one. A
/// choice for a command this build does not know is carried through, and one
/// equal to the command's default is never kept.
///
/// `offered` is the ordered set of commands this device shows anywhere; only
/// they can hold or lose a chord. A default that yields to overrides never
/// takes a chord the person gave another offered command; resetting that
/// command restores it. Values are immutable: every change answers a new one.
public sealed class ShortcutOverrides {
    #region Static Variables

    public const int MaximumOverrides = 256;
    public const int MaximumCommandLength = 64;

    public static readonly ShortcutOverrides None = new(new SortedDictionary<string, ShortcutChord?>(StringComparer.Ordinal));

    #endregion

    #region Variables

    private readonly SortedDictionary<string, ShortcutChord?> chords;

    /// Every choice, by command name in ordinal order.
    public IEnumerable<KeyValuePair<string, ShortcutChord?>> Chords => chords;

    /// Whether the person changed any shortcut, including one this device does not offer.
    public bool IsCustomized => chords.Count > 0;

    #endregion

    #region Constructors

    private ShortcutOverrides(SortedDictionary<string, ShortcutChord?> chords) => this.chords = chords;

    /// The choices `stored` names, the first for each command name, leaving
    /// out names no command could have and anything past the limit.
    public static ShortcutOverrides Restore(IEnumerable<KeyValuePair<string, ShortcutChord?>> stored) {
        ArgumentNullException.ThrowIfNull(stored);
        var chords = new SortedDictionary<string, ShortcutChord?>(StringComparer.Ordinal);
        foreach (var (command, chord) in stored) {
            if (chords.Count >= MaximumOverrides) break;
            if (command.Length is 0 or > MaximumCommandLength) continue;
            chords.TryAdd(command, chord);
        }
        return new(chords);
    }

    #endregion

    #region Actions - Resolution

    /// Each offered command's chord now, in `offered` order.
    public IReadOnlyList<ShortcutBinding> Bindings(IReadOnlyList<ShortcutCommand> offered, DevicePlatform platform) =>
        [.. offered.Select(command => new ShortcutBinding(command, Effective(command, offered, platform)?.Keys,
            chords.ContainsKey(command.Name)))];

    /// The chord `command` answers to now.
    public ShortcutChord? Effective(ShortcutCommand command, IReadOnlyList<ShortcutCommand> offered, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(offered);
        if (chords.TryGetValue(command.Name, out var custom)) return custom;
        if (command.DefaultShortcut(platform) is not { } fallback) return null;
        var chord = ShortcutChord.Of(fallback.Keys);
        if (fallback.YieldsToOverrides && offered.Any(other => chords.TryGetValue(other.Name, out var taken) && taken == chord)) return null;
        return chord;
    }

    /// The other offered commands that answer to `chord` now.
    public IReadOnlyList<ShortcutCommand> Holders(ShortcutChord chord, ShortcutCommand command, IReadOnlyList<ShortcutCommand> offered,
        DevicePlatform platform) =>
        [.. offered.Where(other => other != command && Effective(other, offered, platform) == chord)];

    #endregion

    #region Actions - Changes

    /// `command` answering to `chord`. Throws `Rejected` with `ShortcutInUse`
    /// naming every other offered command that answers to it.
    public ShortcutOverrides Assigning(ShortcutCommand command, ShortcutChord chord, IReadOnlyList<ShortcutCommand> offered,
        DevicePlatform platform) {
        var holders = Holders(chord, command, offered, platform);
        if (holders.Count > 0) throw new Rejected(new ShortcutInUse(holders));
        return Setting(command, chord, platform);
    }

    /// `command` answering to `chord`, which every other offered command that
    /// answered to it gives up.
    public ShortcutOverrides Reassigning(ShortcutCommand command, ShortcutChord chord, IReadOnlyList<ShortcutCommand> offered,
        DevicePlatform platform) {
        var revised = this;
        foreach (var holder in Holders(chord, command, offered, platform)) revised = revised.Setting(holder, null, platform);
        return revised.Setting(command, chord, platform);
    }

    /// `command` answering to no chord.
    public ShortcutOverrides Unassigning(ShortcutCommand command, DevicePlatform platform) => Setting(command, null, platform);

    /// `command` back on its default.
    public ShortcutOverrides Resetting(ShortcutCommand command) {
        ArgumentNullException.ThrowIfNull(command);
        if (!chords.ContainsKey(command.Name)) return this;
        var revised = new SortedDictionary<string, ShortcutChord?>(chords, StringComparer.Ordinal);
        revised.Remove(command.Name);
        return new(revised);
    }

    /// The choices with `chord` for `command`; one equal to its default is
    /// no choice at all.
    private ShortcutOverrides Setting(ShortcutCommand command, ShortcutChord? chord, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(command);
        ArgumentNullException.ThrowIfNull(platform);
        var fallback = command.DefaultShortcut(platform) is { } keys ? ShortcutChord.Of(keys.Keys) : null;
        var revised = new SortedDictionary<string, ShortcutChord?>(chords, StringComparer.Ordinal);
        if (chord == fallback) revised.Remove(command.Name);
        else revised[command.Name] = chord;
        return new(revised);
    }

    #endregion

    #region Actions - Equality

    /// Whether `other` holds the same choices.
    public bool SameAs(ShortcutOverrides? other) =>
        other is not null && chords.Count == other.chords.Count
        && chords.All(entry => other.chords.TryGetValue(entry.Key, out var chord) && chord == entry.Value);

    #endregion
}
