using CrestCore.Application;

namespace CrestCore.Contracts;

/// Carries the link preferences an installed release kept in its defaults
/// into the device store, once, and publishes them. `Preferences` is the
/// document that release saved under `crest.link-preferences.v1`, or null when
/// it saved none; the release's own copy stays where it is. A value this build
/// cannot read keeps its default. A device that adopted them before, or keeps
/// no file, adopts nothing and still publishes its preferences, so the
/// platform reads them from launch.
public sealed record AdoptLinkPreferences(byte[]? Preferences) : LinkIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        lock (device.Gate) {
            Adopt(device);
            turn.Changes.Publish(new LinkPreferencesChanged(device.Links));
        }
    }

    /// Carries the preferences an installed release kept into the device store
    /// once, in place of the defaults. The preferences and the adoption's
    /// marker are saved together, so a launch that could not save them adopts
    /// them again. The caller holds the device lock.
    private void Adopt(Device device) {
        if (device.Storage is not { } target || device.Adopted.Contains(DeviceAdoption.LinkPreferences)) return;
        device.Links = LegacyLinkPreferencesDocument.Read(Preferences) ?? device.Links;
        device.Adopted.Add(DeviceAdoption.LinkPreferences);
        target.EnqueueDevice(device.Records());
    }

    #endregion
}
