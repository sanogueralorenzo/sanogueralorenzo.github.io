using CrestCore.Application;

namespace CrestCore.Contracts;

/// Derived activity from the native ledger, used only by quit preparation.
public sealed record SetDownloadActivity(int Count) : Intent {
    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(_ => app.SetDownloadActivity(Count));
}
