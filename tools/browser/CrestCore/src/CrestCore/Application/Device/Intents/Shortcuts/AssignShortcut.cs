using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Binds `Keys` to `Command`. Refused while another offered command answers to
/// them, so nothing loses its chord until the person confirms with
/// `ReassignShortcut`.
public sealed record AssignShortcut(ShortcutCommand Command, KeyCombination Keys) : ShortcutIntent {
    #region Actions - Device

    internal override void Apply(Device device, ShortcutTurn turn) =>
        device.ReviseShortcuts(turn, shortcuts => shortcuts.Assigning(Command, Device.Chord(Keys), turn.Offered, device.Platform));

    #endregion
}
