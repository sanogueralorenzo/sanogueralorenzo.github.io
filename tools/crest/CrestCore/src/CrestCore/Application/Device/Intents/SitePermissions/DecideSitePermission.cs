using CrestCore.Application;

namespace CrestCore.Contracts;

/// Records the person's answer for `Permission` at `Origin` in a Space.
/// `Detail` narrows a capability a site can ask for more than one way, such as
/// the URL scheme behind one external-app hand-off; null is the site-wide rule.
/// Ask clears both the session and the saved choice; a session answer
/// overrides the saved choice until the process ends without replacing it; a
/// persistent answer replaces both and keeps an existing record's identity.
public sealed record DecideSitePermission(Guid SpaceId, SiteOrigin Origin, SitePermission Permission, string? Detail,
    SitePermissionDecision Decision) : SitePermissionIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var (keeps, locked) = device.ChoiceScope(SpaceId);
        if (locked) throw new Rejected(new SpaceLocked(SpaceId));
        lock (device.Gate) {
            var outcome = (keeps ? device.KeptPermissions : device.PassingPermissions).Set(SpaceId, Origin, Permission, Detail,
                Decision, turn.Ids.Next(), StoredSessionCodec.Seconds(turn.Now));
            if (keeps && outcome.PersistenceChanged) device.Storage?.EnqueueDevice(device.Records());
            device.PublishPermissions(outcome, turn.Changes);
        }
    }

    #endregion
}
