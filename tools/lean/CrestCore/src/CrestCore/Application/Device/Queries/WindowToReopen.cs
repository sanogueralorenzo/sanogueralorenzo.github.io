using CrestCore.Application;

namespace CrestCore.Contracts;

/// The window the Dock icon, or opening the app again, brings to the person,
/// over this device's windows as the platform stacks them, frontmost first
/// (`WindowIds`): the frontmost open over the persistent session, or with none
/// open, the saved window used last that is not open, or a new one, which
/// opens.
public sealed record WindowToReopen(IReadOnlyList<Guid> WindowIds) : Query<ReopenedWindow> {
    #region Actions - Answering

    internal override ReopenedWindow Answer(CrestApp app) {
        if (app.Device.FrontWindow(WindowIds) is { } front) return new(front.Id, OpensWindow: false);
        lock (app.Device.Gate) return new(app.Device.WindowToOpen(app.Ids), OpensWindow: true);
    }

    #endregion
}
