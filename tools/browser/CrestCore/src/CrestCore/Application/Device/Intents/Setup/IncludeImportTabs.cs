using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Brings the tabs `TabIds` of the reviewed Space `SourceSpaceId`, or leaves
/// them out. Bringing a tab brings its Space.
public sealed record IncludeImportTabs(Guid SourceSpaceId, IReadOnlyList<Guid> TabIds, bool Included) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.IncludingTabs(SourceSpaceId, TabIds, Included, session)));

    #endregion
}
