using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lets agents reach `SpaceId`, or stops them; agents using its tabs let them
/// go. Refused with `AgentSpaceUnavailable` for a Space that is not one of the
/// person's own session, or is being deleted.
public sealed record AllowAgentSpace(Guid SpaceId, bool Allowed) : AgentIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        if (Allowed && !device.OffersToAgents(SpaceId)) throw new Rejected(new AgentSpaceUnavailable(SpaceId));
        device.ReviseAgents(turn.Changes, preferences => preferences.Allowing(SpaceId, Allowed));
    }

    #endregion
}
