using CrestCore.Contracts;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    /// Like a renderer report, a page record may arrive while a transaction
    /// holds the session. The session retains its existing ordering and refusal
    /// rules; a vanished workspace simply takes no record.
    internal IReadOnlyList<Change> RecordPage(Guid workspaceId, PageEdit edit) {
        IReadOnlyList<Change> result;
        lock (gate) {
            var recorded = device.Attached(workspaceId)?.Apply(edit) ?? [];
            result = [.. TakePending(), .. recorded];
        }
        WakeIfOwed();
        WakeForRequestedTurn();
        return result;
    }
}
