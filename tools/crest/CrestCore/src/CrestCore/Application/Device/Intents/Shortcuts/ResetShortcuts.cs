using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Forgets every shortcut choice, including those for commands this device
/// does not offer.
public sealed record ResetShortcuts() : ShortcutIntent {
    #region Actions - Device

    internal override void Apply(Device device, ShortcutTurn turn) =>
        device.ReviseShortcuts(turn, _ => ShortcutOverrides.None);

    #endregion
}
