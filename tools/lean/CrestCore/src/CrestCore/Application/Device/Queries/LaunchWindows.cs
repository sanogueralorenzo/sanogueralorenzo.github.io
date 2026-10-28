using CrestCore.Application;

namespace CrestCore.Contracts;

/// The saved windows to reopen, or the last-used window when none were left open.
public sealed record LaunchWindows() : Query<LaunchWindowPlan> {
    #region Actions - Answering

    /// The windows the device store reopens with the frontmost last.
    internal override LaunchWindowPlan Answer(CrestApp app) {
        var windows = app.Device.LaunchWindows(app.Ids);
        return new(windows, windows[^1]);
    }

    #endregion
}
