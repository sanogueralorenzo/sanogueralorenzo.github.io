using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Checkpoint repair and retention operate on detached sessions, at the stored
/// session's JSON boundary; a `SessionRepair` mends each Space. Native image
/// bytes never enter the session; the result identifies which live assets to
/// reattach, even when repair changed a colliding tab or Space identity.
public static class NativeSessionMaintenance {
    #region Types

    /// Where a repaired tab's native assets come from.
    internal sealed record TabOrigin(int SpaceIndex, int TabIndex, Guid SourceSpaceId, Guid SourceTabId);

    #endregion

    #region Actions - Session maintenance

    /// The repaired session and positional asset references: `{"session", "assets"}`.
    public static JsonObject Repair(JsonObject source, double now, JsonObject? emptySpace = null, IIdSource? ids = null) {
        if (!double.IsFinite(now)) throw new ArgumentOutOfRangeException(nameof(now), now, "A time is a finite number of seconds.");
        var repaired = Repair(StoredSessionCodec.DecodeSession(source), StoredSessionCodec.Date(now),
            emptySpace is null ? null : StoredSessionCodec.DecodeSpace(emptySpace), ids ?? new SystemIdSource(), out var origins);
        return Answer(repaired, origins);
    }

    /// A repaired session with the positional references to the native assets
    /// each of its tabs keeps: `{"session", "assets"}`.
    internal static JsonObject Answer(SessionState repaired, IReadOnlyList<TabOrigin> origins) => new() {
        ["session"] = StoredSessionCodec.Encode(repaired),
        ["assets"] = new JsonArray(origins.Select(origin => (JsonNode?)new JsonObject {
            ["spaceIndex"] = origin.SpaceIndex,
            ["tabIndex"] = origin.TabIndex,
            ["sourceSpaceID"] = StoredSessionCodec.WrappedIdentity(origin.SourceSpaceId),
            ["sourceTabID"] = StoredSessionCodec.WrappedIdentity(origin.SourceTabId)
        }).ToArray())
    };

    /// Each tab of `repaired` whose identity `Repair` changed, with the tab
    /// whose native assets it keeps.
    internal static IReadOnlyList<(Guid Source, Guid Copy)> Copies(SessionState repaired, IReadOnlyList<TabOrigin> origins) => [.. origins
        .Select(origin => (Source: origin.SourceTabId, Copy: repaired.Spaces[origin.SpaceIndex].Tabs[origin.TabIndex].Id))
        .Where(pair => pair.Source != pair.Copy)];

    /// Gives every Space, profile and tab its own identity, repairs folder trees,
    /// pin limits, split runs and split metadata, keeps a Space that is being
    /// deleted exactly as it was, and adds a Space when none would remain.
    internal static SessionState Repair(SessionState source, DateTimeOffset now, SpaceState? emptySpace, IIdSource ids,
        out IReadOnlyList<TabOrigin> origins) {
        var pending = source.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        var spaces = source.Spaces.ToList();
        if (spaces.Count == 0 || spaces.All(space => pending.Contains(space.Id))) spaces.Add(SessionRepair.Empty(emptySpace, ids, now));
        var repair = new SessionRepair(ids, now);
        // Cleanup that is under way keeps the Space exactly as it was.
        IReadOnlyList<SpaceState> repaired = [.. spaces.Select((space, spaceIndex) =>
            pending.Contains(space.Id) ? repair.Kept(space, spaceIndex) : repair.Repaired(space, spaceIndex))];
        origins = repair.Origins;
        // A launch Space that is gone falls back to the first Space that stays.
        var active = repaired.Select(space => space.Id).ToHashSet();
        var launch = source.DefaultSpaceId is { } chosen && active.Contains(chosen)
            ? chosen : repaired.First(space => !pending.Contains(space.Id)).Id;
        return source with { Spaces = repaired, DefaultSpaceId = launch };
    }

    /// `seed` repaired as a stored session is when it loads, stamped as the
    /// session stores `now`, with the tabs the repair gave new identities.
    /// Throws `Rejected` with `InvalidSession` naming the first rule it
    /// breaks that the repair cannot mend.
    internal static SessionState RepairSeed(SessionState seed, DateTimeOffset now, IIdSource ids, out IReadOnlyList<TabOrigin> origins) {
        var stamped = StoredSessionCodec.Date(StoredSessionCodec.Seconds(now));
        SessionState repaired;
        try {
            repaired = Repair(seed, stamped, null, ids, out origins);
        } catch (BrowserRuleException) {
            // A Space whose deletion is under way keeps its identities, so one
            // another Space shares is the seed's to fix.
            throw new Rejected(new InvalidSession(SessionIdentities.Flaw(seed) ?? SessionFlaw.Unreadable));
        }
        return SessionIdentities.Flaw(repaired) is { } flaw ? throw new Rejected(new InvalidSession(flaw)) : repaired;
    }

    /// Removes history and archive records older than each Space keeps them;
    /// a Space that is being deleted keeps everything.
    internal static SessionState Retain(SessionState session, DateTimeOffset at, out bool removed) {
        var pending = session.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        bool changed = false;
        IReadOnlyList<SpaceState> spaces = [.. session.Spaces.Select(space => {
            if (pending.Contains(space.Id)) return space;
            var retained = space.Retained(at);
            changed |= !ReferenceEquals(retained, space);
            return retained;
        })];
        removed = changed;
        return session with { Spaces = spaces };
    }

    #endregion
}
