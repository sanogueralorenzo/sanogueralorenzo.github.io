using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// What one shortcut intent needs: where it publishes the bindings, and the
/// commands this device offers, which the bindings are read over.
internal sealed record ShortcutTurn(ChangeFeed Changes, IReadOnlyList<ShortcutCommand> Offered);

#endregion

/// This device's shortcut choices, which the device store keeps. What a
/// choice binds is read on the device's platform, over the commands its
/// default engine offers.
internal sealed partial class Device {
    #region Variables

    private ShortcutOverrides shortcuts = ShortcutOverrides.None;
    internal ShortcutOverrides ShortcutOverrides { get => shortcuts; set => shortcuts = value; }

    #endregion

    #region Actions - Shortcut intents

    /// Runs one shortcut intent over the commands this device offers.
    public void Handle(ShortcutIntent intent, ShortcutTurn turn) => intent.Apply(this, turn);

    /// Keeps the overrides `revise` makes of the device's own, and publishes
    /// the bindings over the offered commands when any of them changed.
    internal void ReviseShortcuts(ShortcutTurn turn, Func<ShortcutOverrides, ShortcutOverrides> revise) {
        lock (gate) {
            var revised = revise(shortcuts);
            if (revised.SameAs(shortcuts)) return;
            var before = Shortcuts(turn.Offered);
            shortcuts = revised;
            storage?.EnqueueDevice(Records());
            var after = Shortcuts(turn.Offered);
            if (after.IsCustomized != before.IsCustomized || !after.Bindings.SequenceEqual(before.Bindings)) turn.Changes.Publish(after);
        }
    }

    /// The bindings over `offered` when the commands this device offers
    /// changed from `before`, or null when no binding differs.
    public ShortcutsChanged? ShortcutsAfter(IReadOnlyList<ShortcutCommand> before, IReadOnlyList<ShortcutCommand> offered) {
        lock (gate) {
            var previous = Shortcuts(before);
            var next = Shortcuts(offered);
            return next.Bindings.SequenceEqual(previous.Bindings) ? null : next;
        }
    }

    /// Every offered command's binding. The caller holds the device lock.
    internal ShortcutsChanged Shortcuts(IReadOnlyList<ShortcutCommand> offered) =>
        new(shortcuts.Bindings(offered, platform), shortcuts.IsCustomized);

    /// The chord `keys` spell, or `InvalidShortcut` for keys that can never be one.
    internal static ShortcutChord Chord(KeyCombination keys) =>
        ShortcutChord.Usable(keys) ?? throw new Rejected(new InvalidShortcut(keys));

    #endregion
}
