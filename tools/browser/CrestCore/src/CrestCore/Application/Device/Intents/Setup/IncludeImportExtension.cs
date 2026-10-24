using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Installs the extension `ExtensionId` that the reviewed Space
/// `SourceSpaceId` offers once it is imported, or leaves it out.
public sealed record IncludeImportExtension(Guid SourceSpaceId, string ExtensionId, bool Included) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) =>
        Device.Editing(flow, review => review.IncludingExtension(SourceSpaceId, ExtensionId, Included, session)));

    #endregion
}
