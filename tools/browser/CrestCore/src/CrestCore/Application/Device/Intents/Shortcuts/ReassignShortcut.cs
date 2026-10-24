using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Binds `Keys` to `Command`, taking them from every other offered command
/// that answers to them, which is left without a chord.
public sealed record ReassignShortcut(ShortcutCommand Command, KeyCombination Keys) : ShortcutIntent {
    #region Actions - Device

    internal override void Apply(Device device, ShortcutTurn turn) =>
        device.ReviseShortcuts(turn, shortcuts => shortcuts.Reassigning(Command, Device.Chord(Keys), turn.Offered, device.Platform));

    #endregion
}
