using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Adds a new Space at the end of the manual setup, named for its place, such
/// as "Space 2", and wearing the accents in turn in the look setup chose.
/// Refused with `SpaceLimitReached` when the setup holds as many Spaces as a
/// workspace may.
public sealed record AddSetupSpace() : SetupDraftIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSetup(turn.Changes, draft => draft.Adding(turn.Ids.Next, device.SetupLook));

    #endregion
}
