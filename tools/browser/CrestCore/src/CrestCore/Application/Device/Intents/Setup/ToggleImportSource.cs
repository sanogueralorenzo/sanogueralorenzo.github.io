using CrestCore.Application;

namespace CrestCore.Contracts;

/// Chooses `Source` to import from, or leaves it out when chosen. Any review
/// or failure goes, and setup shows the browsers again.
public sealed record ToggleImportSource(ImportSource Source) : SetupFlowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseFlow(turn.Changes, (flow, _) => Toggled(Device.Idle(flow)));

    /// `flow` with `Source` chosen or left out. Any review or failure goes,
    /// and the queue starts over from the chosen browsers.
    private SetupFlowState Toggled(SetupFlowState flow) {
        var selected = flow.Selected.Contains(Source) ? flow.Selected.Where(chosen => chosen != Source) : flow.Selected.Append(Source);
        var chosen = selected.ToHashSet();
        return flow with {
            Step = SetupStep.ImportBrowser,
            Phase = SetupPhase.Idle,
            Selected = [.. chosen.OrderBy(Position(flow))],
            Queue = new([.. flow.Offered.Where(chosen.Contains)], 0),
            Source = null,
            Review = null,
            Failure = null
        };
    }

    /// Where a browser stands among the browsers `flow` offers.
    private static Func<ImportSource, int> Position(SetupFlowState flow) => source => {
        int index = flow.Offered.ToList().IndexOf(source);
        return index < 0 ? int.MaxValue : index;
    };

    #endregion
}
