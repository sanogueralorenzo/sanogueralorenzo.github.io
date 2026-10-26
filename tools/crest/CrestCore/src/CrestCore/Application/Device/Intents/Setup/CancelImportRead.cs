using CrestCore.Application;

namespace CrestCore.Contracts;

/// Stops reading the current browser and goes back to choosing browsers.
public sealed record CancelImportRead() : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) =>
        flow.Phase == SetupPhase.Reading
            ? flow with { Phase = SetupPhase.Idle, Step = SetupStep.ImportBrowser, Source = null, Failure = null } : flow);

    #endregion
}
