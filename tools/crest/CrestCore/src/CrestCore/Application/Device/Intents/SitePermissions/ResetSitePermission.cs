using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record ResetSitePermission(Guid RecordId) : SitePermissionIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        lock (device.Gate) {
            var kept = device.KeptPermissions.ResetRecord(RecordId);
            if (kept.PersistenceChanged) device.Storage?.EnqueueDevice(device.Records());
            device.PublishPermissions(kept.Changes.Count > 0 ? kept : device.PassingPermissions.ResetRecord(RecordId), turn.Changes);
        }
    }

    #endregion
}
