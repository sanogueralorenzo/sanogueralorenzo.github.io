using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives the Spaces setup makes from here on `Look`: the manual setup's new
/// Spaces and the first launch's disposable Spaces, and each Space an import
/// brings in new. A manual setup the device already holds takes it too.
public sealed record ChooseSetupLook(SetupLook Look) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) => {
        var idle = Device.Idle(flow);
        if (idle.Look == Look) return flow;
        device.RestyleSetup(flow.WorkspaceId, session, idle.Look, Look, turn.Changes);
        return idle with { Look = Look };
    });

    #endregion
}
