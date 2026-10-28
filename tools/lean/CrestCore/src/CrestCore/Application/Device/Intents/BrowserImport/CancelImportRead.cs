using CrestCore.Application;

namespace CrestCore.Contracts;

/// Stops reading the current browser and goes back to choosing browsers.
public sealed record CancelImportRead() : BrowserImportIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) =>
        flow.Phase == ImportPhase.Reading
            ? flow with { Phase = ImportPhase.Idle, Step = ImportStep.ImportBrowser, Source = null, Failure = null } : flow);

    #endregion
}
