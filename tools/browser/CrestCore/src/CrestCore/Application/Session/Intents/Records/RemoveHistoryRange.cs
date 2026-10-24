using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Removes the history entries of a Space last visited from `Start` up to,
/// but not including, `End`. A range that ends before it starts is refused
/// with `InvalidDateRange`.
public sealed record RemoveHistoryRange(Guid WorkspaceId, Guid SpaceId, DateTimeOffset Start, DateTimeOffset End)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (End < Start) throw new Rejected(new InvalidDateRange());
        var removed = WithinRange(workspace.Seconds(space.History.Select(entry => entry.LastVisitedAt)),
            StoredSessionCodec.Seconds(Start), StoredSessionCodec.Seconds(End)).ToHashSet();
        return new(NativeSessionAuthority.Replacing(turn.Basis, workspace.WithoutHistory(space, (_, index) => removed.Contains(index))),
            SyncStaging.Deletion);
    }

    /// The indices of `timestamps` from `start` up to, but not including,
    /// `end`. Callers apply the returned indices to their existing value
    /// snapshots. Every time is the stored seconds of a date, so each is
    /// finite.
    internal static IReadOnlyList<int> WithinRange(IReadOnlyList<double> timestamps, double start, double end) =>
        Enumerable.Range(0, timestamps.Count).Where(i => timestamps[i] >= start && timestamps[i] < end).ToArray();

    #endregion
}
