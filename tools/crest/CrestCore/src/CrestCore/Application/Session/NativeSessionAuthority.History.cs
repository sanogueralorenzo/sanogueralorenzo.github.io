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

    #endregion
}
