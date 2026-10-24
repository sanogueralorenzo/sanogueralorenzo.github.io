using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Brings the saved passwords that belong with the reviewed Space
/// `SourceSpaceId`, or leaves them out.
public sealed record IncludeImportPasswords(Guid SourceSpaceId, bool Included) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.IncludingPasswords(SourceSpaceId, Included, session)));

    #endregion
}
