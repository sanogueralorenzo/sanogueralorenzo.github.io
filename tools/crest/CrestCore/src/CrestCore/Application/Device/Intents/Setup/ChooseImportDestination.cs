using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Makes the reviewed Space `SourceSpaceId` join the existing Space
/// `DestinationSpaceId`, taking that Space's name and look, or come in as a new
/// Space with its own when null.
public sealed record ChooseImportDestination(Guid SourceSpaceId, Guid? DestinationSpaceId) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.ChoosingDestination(SourceSpaceId, DestinationSpaceId, session, flow.Look)));

    #endregion
}
