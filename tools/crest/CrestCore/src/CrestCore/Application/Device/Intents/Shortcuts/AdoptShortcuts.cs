using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Carries the shortcut choices an installed release kept in its defaults
/// into the device store, once, and publishes every offered command's chord.
/// `Overrides` is the document that release saved under
/// `crest.keyboard-shortcuts.v1`, or null when it saved none. An entry this
/// build cannot read is left out; one for a command it does not know is kept.
/// The store is written before the intent returns; a device that adopted them
/// before, or keeps no file, adopts nothing and still publishes its bindings.
public sealed record AdoptShortcuts(byte[]? Overrides) : ShortcutIntent {
    #region Actions - Device

    internal override void Apply(Device device, ShortcutTurn turn) {
        lock (device.Gate) {
            Adopt(device);
            turn.Changes.Publish(device.Shortcuts(turn.Offered));
        }
    }

    /// Carries the choices an installed release kept into the device store
    /// once, after any the store already holds, and saves them before
    /// returning. The caller holds the device lock.
    private void Adopt(Device device) {
        if (device.Storage is not { } target || device.Adopted.Contains(DeviceAdoption.Shortcuts)) return;
        var merged = ShortcutOverrides.Restore([.. device.ShortcutOverrides.Chords, .. LegacyShortcutDocument.Read(Overrides)]);
        var carried = device.Records().Adopting(DeviceAdoption.Shortcuts) with { Shortcuts = merged };
        try {
            target.SaveDevice(carried);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
        device.ShortcutOverrides = merged;
        device.Adopted.Add(DeviceAdoption.Shortcuts);
        // Records handed to the store before this carry nothing adopted; these supersede them.
        target.EnqueueDevice(device.Records());
    }

    #endregion
}
