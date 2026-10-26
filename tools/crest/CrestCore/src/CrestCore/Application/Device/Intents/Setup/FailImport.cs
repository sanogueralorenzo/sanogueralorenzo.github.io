using CrestCore.Application;

namespace CrestCore.Contracts;

/// Reading or importing `Source` failed for `Reason`, in the words of what
/// refused it, `Detail`, when something did. Setup goes back to the step and
/// phase that can try again.
public sealed record FailImport(ImportSource Source, SetupFailureReason Reason, string? Detail) : SetupFlowIntent {
    #region Actions - Device

    /// The flow goes back where the person can try again.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) => {
        var failure = new SetupFailure(Reason, Source, Detail);
        return Reason.ReturnsToReview && flow.Review is not null
            ? flow with { Step = SetupStep.Review, Phase = SetupPhase.Reviewing, Failure = failure }
            : flow with { Step = SetupStep.ImportBrowser, Phase = SetupPhase.Idle, Source = null, Failure = failure };
    });

    #endregion
}
