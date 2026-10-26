using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows `Step`: the step Back or Next leads to, or another the person picked.
/// The review needs an import to review; the manual-setup step starts the
/// manual setup, or goes on with the one the device holds.
public sealed record ShowSetupStep(SetupStep Step) : SetupFlowIntent {
    #region Actions - Device

    /// The review needs a review; the manual-setup step starts the manual setup
    /// or goes on with it.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) => {
        var idle = Device.Idle(flow);
        if (Step == SetupStep.Review && flow.Review is null) return flow;
        if (Step == SetupStep.ManualSetup)
            device.BeginSetup(flow.WorkspaceId, session, startsOver: false, flow.Look, turn.Changes, turn.Ids);
        return idle with { Step = Step, Phase = Step == SetupStep.Review ? SetupPhase.Reviewing : SetupPhase.Idle };
    });

    #endregion
}
