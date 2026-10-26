using CrestCore.Application;

namespace CrestCore.Contracts;

/// Starts importing the review, before the platform reads the passwords it
/// brings and sends `ImportReviewedSpaces`.
///
/// Refused with `NoIncludedSpaces` when the review brings no Space.
public sealed record BeginImportCommit() : SetupFlowIntent {
    #region Actions - Device

    /// The flow imports its review. Throws `Rejected` with `NoIncludedSpaces`
    /// for a review that brings no Space.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) => {
        var idle = Device.Idle(flow);
        if (idle.Review is not { } review) throw new Rejected(new NoSetup());
        if (!review.HasIncludedSpaces) throw new Rejected(new NoIncludedSpaces());
        return idle with { Phase = SetupPhase.Committing, Failure = null };
    });

    #endregion
}
