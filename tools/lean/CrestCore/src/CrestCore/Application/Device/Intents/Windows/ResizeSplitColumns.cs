using CrestCore.Application;

namespace CrestCore.Contracts;

/// Records the share of the width each column of a split group takes in one
/// window. Shares that drift from summing to one are normalized; a list that
/// cannot describe columns is refused with `InvalidSplitColumnShares`.
public sealed record ResizeSplitColumns(Guid WindowId, Guid GroupId, IReadOnlyList<double> Shares) : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var session = device.Workspace(window.WorkspaceId).Current;
        if (Window.SplitShares(Shares) is null) throw new Rejected(new InvalidSplitColumnShares());
        lock (device.Gate) Device.Publish(device.Changing([window], resized => {
            resized.Resize(GroupId, Shares);
            resized.Repair(session);
        }, session), turn.Changes);
    }

    #endregion
}
