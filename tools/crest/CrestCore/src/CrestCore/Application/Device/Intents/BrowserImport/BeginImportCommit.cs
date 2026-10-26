using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record BeginImportCommit() : BrowserImportIntent {
    #region Actions - Device

    /// The flow imports its review. Throws `Rejected` with `NoIncludedSpaces`
    /// for a review that brings no Space.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, _) => {
        var idle = Device.Idle(flow);
        if (idle.Review is not { } review) throw new Rejected(new NoBrowserImport());
        if (!review.HasIncludedSpaces) throw new Rejected(new NoIncludedSpaces());
        return idle with { Phase = ImportPhase.Committing, Failure = null };
    });

    #endregion
}
