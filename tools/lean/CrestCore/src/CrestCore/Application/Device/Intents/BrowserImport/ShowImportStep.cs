using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows an import stage, allowing review only after source data was read.
public sealed record ShowImportStep(ImportStep Step) : BrowserImportIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) => {
        var idle = Device.Idle(flow);
        if (Step == ImportStep.Review && flow.Review is null) return flow;
        return idle with { Step = Step, Phase = Step == ImportStep.Review ? ImportPhase.Reviewing : ImportPhase.Idle };
    });

    #endregion
}
