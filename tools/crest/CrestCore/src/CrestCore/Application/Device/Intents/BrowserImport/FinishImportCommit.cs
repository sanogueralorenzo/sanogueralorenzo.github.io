using CrestCore.Application;

namespace CrestCore.Contracts;

/// Records a completed import and advances to the next selected browser.
public sealed record FinishImportCommit() : BrowserImportIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) => {
        if (flow.Phase != ImportPhase.Committing || flow.Review is not { } review) return flow;
        var summary = new ImportSummary(review.IncludedTabCount,
            review.Spaces.Count(space => space.Included));
        var queue = flow.Queue is { } current ? current with { Index = current.Index + 1 } : null;
        var done = flow with {
            Phase = ImportPhase.Idle,
            Selected = [.. flow.Selected.Where(source => source != review.Source)],
            Queue = queue,
            Source = null,
            Review = null,
            Failure = null,
            Summary = summary
        };
        if (queue?.Current is { } next) return done with { Step = ImportStep.ImportBrowser, Phase = ImportPhase.Reading, Source = next };
        return done with { Step = ImportStep.Complete };
    });

    #endregion
}
