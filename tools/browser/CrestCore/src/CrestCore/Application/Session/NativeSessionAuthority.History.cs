using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// When the session was last swept, and the retention each Space had then.
    internal sealed record SweepMark(DateTimeOffset At, IReadOnlyList<SpaceRetention> Retention) {
        #region Actions - Throttling

        /// Whether a sweep at `now` of `session` would repeat this one: it comes
        /// less than `MinimumSweepSpacing` later, and no Space's retention
        /// changed. A clock that went backwards never holds a sweep back.
        public bool Covers(DateTimeOffset now, SessionState session) =>
            now >= At && now - At < MinimumSweepSpacing && Retention.SequenceEqual(SpaceRetention.Of(session));

        #endregion
    }

    /// What a Space keeps and for how long.
    internal sealed record SpaceRetention(Guid SpaceId, CurrentTabCleanup Cleanup, DataRetentionPreferences Records) {
        #region Actions - Reading

        public static IReadOnlyList<SpaceRetention> Of(SessionState session) => [.. session.Spaces.Select(space =>
            new SpaceRetention(space.Id, space.Settings.BrowsingPreferences.CurrentTabCleanup, space.Settings.BrowsingPreferences.DataRetention))];

        #endregion
    }

    #endregion

    #region Variables

    /// The shortest gap between two sweeps of one session. Windows becoming
    /// active together, or an activation landing on a periodic sweep, sweep once.
    private static readonly TimeSpan MinimumSweepSpacing = TimeSpan.FromMinutes(1);

    /// The last sweep this session ran; null until it runs one.
    private SweepMark? lastSweep;

    /// The last sweep this session ran, which a sweep it would repeat skips.
    internal SweepMark? LastSweep => lastSweep;

    #endregion

    #region Actions - History

    internal SpaceState WithoutHistory(SpaceState space, Func<HistoryEntryState, bool> removes) =>
        WithoutHistory(space, (entry, _) => removes(entry));

    internal SpaceState WithoutHistory(SpaceState space, Func<HistoryEntryState, int, bool> removes) {
        IReadOnlyList<HistoryEntryState> kept = [.. space.History.Where((entry, index) => !removes(entry, index))];
        return kept.Count == space.History.Count ? space : space with { History = kept };
    }

    #endregion

    #region Actions - Retention

    /// The tabs cleanup keeps open in this workspace however long they went
    /// unused: those its windows show or its saved windows will show, those
    /// whose pages run media, such as a video playing in Picture in Picture or
    /// a screen being shared, and those an agent uses.
    internal IReadOnlySet<Guid>? TabsCleanupKeeps(SessionTurn turn) {
        var shown = Device?.ShownTabs(WorkspaceId);
        var media = turn.Pages?.TabsRunningMedia(WorkspaceId);
        var agents = Device?.AgentTabs;
        IEnumerable<Guid>? kept = null;
        foreach (var set in new[] { shown, media, agents }) {
            if (set is { Count: > 0 }) kept = kept is null ? set : kept.Union(set);
        }
        return kept?.ToHashSet() ?? shown;
    }

    /// `space` with its open tabs unused for longer than its cleanup lifetime
    /// archived, keeping `kept`: the tabs `TabsCleanupKeeps` names.
    internal SpaceState CleanedUp(SpaceState space, DateTimeOffset now, IReadOnlySet<Guid>? kept) {
        if (space.Settings.BrowsingPreferences.CurrentTabCleanup.Lifetime is not { } lifetime) return space;
        var edited = BrowserTabCollection.Restore(space);
        edited.CleanupCurrentTabs(null, lifetime, now, kept?.ToArray());
        return space.Tabs.SequenceEqual(edited.TabStates) ? space : edited.Capture(space);
    }

    /// `space` without the history and archive entries older than it keeps them.
    internal SpaceState Expired(SpaceState space, DateTimeOffset now) {
        var retention = space.Settings.BrowsingPreferences.DataRetention;
        var seconds = StoredSessionCodec.Seconds(now);
        if (retention.History.Lifetime is { } history) {
            var expired = DataRetention.Expired(Seconds(space.History.Select(entry => entry.LastVisitedAt)), seconds,
                history.TotalSeconds).ToHashSet();
            space = WithoutHistory(space, (_, index) => expired.Contains(index));
        }
        if (retention.Archive.Lifetime is { } archive) {
            var expired = DataRetention.Expired(Seconds(space.ArchivedTabs.Select(archived => archived.ArchivedAt)), seconds,
                archive.TotalSeconds).ToHashSet();
            if (expired.Count > 0) space = space with { ArchivedTabs = [.. space.ArchivedTabs.Where((_, index) => !expired.Contains(index))] };
        }
        return space;
    }

    #endregion

    #region Actions - Dates

    /// The dates as the stored format's seconds, which the removal policies read.
    internal double[] Seconds(IEnumerable<DateTimeOffset> dates) => dates.Select(StoredSessionCodec.Seconds).ToArray();

    #endregion
}
