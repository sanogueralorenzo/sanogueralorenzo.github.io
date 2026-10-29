using CrestCore.Application;

namespace CrestCore.Contracts;

/// Preserves the open windows for next launch once the native quit is allowed.
public sealed record AcceptQuit : Intent {
    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(_ => app.Device.AcceptQuit());
}
