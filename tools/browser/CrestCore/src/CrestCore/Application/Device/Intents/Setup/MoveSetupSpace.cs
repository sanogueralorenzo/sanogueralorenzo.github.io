using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Moves the Space `SpaceId` of the manual setup to where `TargetSpaceId`
/// stands, and makes the workspace take the setup's order.
public sealed record MoveSetupSpace(Guid SpaceId, Guid TargetSpaceId) : SetupDraftIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSetup(turn.Changes, draft => draft.Moving(SpaceId, TargetSpaceId));

    #endregion
}
