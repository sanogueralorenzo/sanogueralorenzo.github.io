using CrestCore.Application;

namespace CrestCore.Contracts;

/// Goes on from choosing browsers: with none chosen, to setting up Spaces by
/// hand; otherwise to reading the next chosen browser, which the platform
/// then reads and hands back in `ReviewImport`.
public sealed record ContinueImport() : SetupFlowIntent {
    #region Actions - Device

    /// The flow goes on from choosing browsers: to the manual setup when none
    /// is chosen, or to reading the next chosen one.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (chosen, session) => {
        var flow = Device.Idle(chosen);
        if (flow.Selected.Count == 0) {
            device.BeginSetup(flow.WorkspaceId, session, startsOver: false, flow.Look, turn.Changes, turn.Ids);
            return flow with { Step = SetupStep.ManualSetup, Phase = SetupPhase.Idle, Source = null, Failure = null };
        }
        var queue = flow.Queue is { Current: not null } current && current.Sources.Skip(current.Index).ToHashSet().SetEquals(flow.Selected)
            ? current : new SetupImportQueue([.. flow.Offered.Where(flow.Selected.Contains)], 0);
        if (queue.Current is not { } source)
            return flow with {
                Queue = queue,
                Step = SetupStep.ImportBrowser,
                Phase = SetupPhase.Idle,
                Failure = new(SetupFailureReason.SourceUnavailable, null, null)
            };
        return flow with { Queue = queue, Step = SetupStep.ImportBrowser, Phase = SetupPhase.Reading, Source = source, Failure = null };
    });

    #endregion
}
