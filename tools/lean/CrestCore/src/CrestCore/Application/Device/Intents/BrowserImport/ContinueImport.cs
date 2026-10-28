using CrestCore.Application;

namespace CrestCore.Contracts;

/// Reads the next selected browser, whose review the platform supplies.
public sealed record ContinueImport() : BrowserImportIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (chosen, session) => {
        var flow = Device.Idle(chosen);
        if (flow.Selected.Count == 0) return flow;
        var queue = flow.Queue is { Current: not null } current && current.Sources.Skip(current.Index).ToHashSet().SetEquals(flow.Selected)
            ? current : new ImportQueue([.. flow.Offered.Where(flow.Selected.Contains)], 0);
        if (queue.Current is not { } source)
            return flow with {
                Queue = queue,
                Step = ImportStep.ImportBrowser,
                Phase = ImportPhase.Idle,
                Failure = new(ImportFailureReason.SourceUnavailable, null, null)
            };
        return flow with { Queue = queue, Step = ImportStep.ImportBrowser, Phase = ImportPhase.Reading, Source = source, Failure = null };
    });

    #endregion
}
