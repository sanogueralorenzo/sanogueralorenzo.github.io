using CrestCore.Application;

namespace CrestCore.Contracts;

/// Carries the unfinished manual setup an installed release kept in its
/// defaults into the device store, once. `Draft` is the document that release
/// saved under `BrowserManualSetupDraft`, or null when it saved none; the
/// release's own copy stays where it is. Only a platform that keeps an
/// unfinished setup takes it, and one the store already keeps wins. A device
/// that adopted it before, or keeps no file, adopts nothing. The adopted
/// setup waits for setup's manual-setup step, so nothing is published.
public sealed record AdoptSetupDraft(byte[]? Draft) : SetupDraftIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        lock (device.Gate) Adopt(device);
    }

    /// Carries the setup an installed release kept into the device store
    /// once. The caller holds the device lock.
    private void Adopt(Device device) {
        if (device.Storage is not { } target || device.Adopted.Contains(DeviceAdoption.SetupDraft)) return;
        if (device.Platform.KeepsSetupDraft) device.KeptSetupDraft ??= LegacySetupDraftDocument.Read(Draft);
        device.Adopted.Add(DeviceAdoption.SetupDraft);
        target.EnqueueDevice(device.Records());
    }

    #endregion
}
