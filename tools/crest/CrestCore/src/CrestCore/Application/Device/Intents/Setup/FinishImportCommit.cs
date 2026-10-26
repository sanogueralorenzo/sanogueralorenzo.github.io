using CrestCore.Application;

namespace CrestCore.Contracts;

/// The review is imported, with `PasswordCount` of its passwords. Setup goes
/// on to the next chosen browser; after the last, to setting up Spaces by hand
/// when it walks the person through Crest, or else to what it did.
public sealed record FinishImportCommit(int PasswordCount) : SetupFlowIntent {
    #region Actions - Device

    /// Once its review is imported with `PasswordCount` passwords the flow
    /// goes on to the next chosen browser, or after the last to the manual
    /// setup when setup walks the person through Crest, or else to what it did.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) => {
        if (flow.Phase != SetupPhase.Committing || flow.Review is not { } review) return flow;
        var summary = new SetupSummary(IsImport: true, review.IncludedTabCount, Math.Max(PasswordCount, 0),
            review.Spaces.Count(space => space.Included));
        var queue = flow.Queue is { } current ? current with { Index = current.Index + 1 } : null;
        var done = flow with {
            Phase = SetupPhase.Idle,
            Selected = [.. flow.Selected.Where(source => source != review.Source)],
            Queue = queue,
            Source = null,
            Review = null,
            Failure = null,
            Summary = summary
        };
        if (queue?.Current is { } next) return done with { Step = SetupStep.ImportBrowser, Phase = SetupPhase.Reading, Source = next };
        if (!flow.Entry.IsGuided) return done with { Step = SetupStep.Complete };
        device.BeginSetup(flow.WorkspaceId, session, startsOver: false, flow.Look, turn.Changes, turn.Ids);
        return done with { Step = SetupStep.ManualSetup };
    });

    #endregion
}
