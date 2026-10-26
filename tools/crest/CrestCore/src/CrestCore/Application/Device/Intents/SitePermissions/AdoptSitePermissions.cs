using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Carries the site permission choices an installed release kept in its
/// defaults into the device store, once, and publishes every Space's choices.
/// `Records` is the document that release saved under
/// `crest.site-permissions.v1`, or null when it saved none. Entries this build
/// cannot read, repeats of an earlier choice and anything but a persistent
/// answer are left out. The store is written before the intent returns; a
/// device that adopted them before, or keeps no file, adopts nothing and still
/// publishes what it holds.
public sealed record AdoptSitePermissions(byte[]? Records) : SitePermissionIntent {
    #region Actions - Device

    /// Carries the choices an installed release kept into the device store
    /// once, merged after any the store already holds, and saves them before
    /// returning. Every call publishes each Space that holds a choice.
    internal override void Apply(Device device, DeviceTurn turn) {
        lock (device.Gate) {
            if (device.Storage is { } target && !device.Adopted.Contains(DeviceAdoption.SitePermissions)) {
                var merged = new SitePermissionLedger();
                merged.Restore([.. device.KeptPermissions.PersistentRecords, .. SitePermissionDocument.Read(Records)]);
                var carried = device.Records().Adopting(DeviceAdoption.SitePermissions) with { SitePermissions = merged.PersistentRecords };
                try {
                    target.SaveDevice(carried);
                } catch (StorageException error) {
                    throw new Rejected(new SaveFailed(error.Reason));
                }
                device.KeptPermissions.Restore(carried.SitePermissions);
                device.Adopted.Add(DeviceAdoption.SitePermissions);
                // Records handed to the store before this carry nothing adopted; these supersede them.
                target.EnqueueDevice(device.Records());
            }
            foreach (var space in device.KeptPermissions.Spaces.Union(device.PassingPermissions.Spaces))
                turn.Changes.Publish(new SitePermissionsChanged(space, device.PermissionRecords(space), []));
        }
    }

    #endregion
}
