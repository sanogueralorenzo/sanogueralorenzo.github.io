using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Forgets every saved and session choice in one Space, locked, deleted or
/// private alike, so resetting or deleting a Space is never blocked.
public sealed record ResetSpacePermissions(Guid SpaceId) : SitePermissionIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        lock (device.Gate) {
            var kept = device.KeptPermissions.ResetSpace(SpaceId);
            var passing = device.PassingPermissions.ResetSpace(SpaceId);
            if (kept.PersistenceChanged) device.Storage?.EnqueueDevice(device.Records());
            var changed = new SitePermissionOutcome(kept.PersistenceChanged, [.. kept.Changes.Concat(passing.Changes).Distinct()]);
            device.PublishPermissions(changed, turn.Changes);
        }
    }

    #endregion
}
