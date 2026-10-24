using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Prepares the session and journal together. Local edits stage before incoming
/// records; repair and retention finish before either resulting value is returned.
/// Publication and durable storage must accept this pair together.
public sealed record NativeSyncSessionTransition {
    #region Variables

    private readonly JsonObject? legacyLocal;

    public NativeSyncJournal Journal { get; }
    internal SessionState Session { get; }
    internal IReadOnlyList<NativeSessionMaintenance.TabOrigin> Origins { get; }

    /// The legacy native checkpoint answer, encoded only when the caller needs
    /// that boundary. In-process convergence uses Session and Origins directly.
    public JsonObject Materialization => NativeSyncCheckpointCodec.Encode(Session, Origins, legacyLocal);

    #endregion

    #region Constructors

    private NativeSyncSessionTransition(NativeSyncJournal journal, SessionState session,
        IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins, JsonObject? legacyLocal = null) {
        Journal = journal;
        Session = session;
        Origins = origins;
        this.legacyLocal = legacyLocal;
    }

    #endregion

    #region Actions - Sync

    internal static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, JsonObject local, JsonArray incoming,
        bool replacing, double now, JsonObject? emptySpace, SpaceAccessAuthority? access, IIdSource? ids,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        var prepared = Prepare(journal, StoredSessionCodec.DecodeSession(local), incoming, replacing, StoredSessionCodec.Date(now),
            emptySpace is null ? null : StoredSessionCodec.DecodeSpace(emptySpace), access, ids ?? new SystemIdSource(), removals);
        return new(prepared.Journal, prepared.Session, prepared.Origins, local.DeepClone().AsObject());
    }

    /// Stage local edits, accept incoming records, materialize and repair a typed
    /// session, retaining local deletion work and device preferences throughout.
    internal static NativeSyncSessionTransition Prepare(NativeSyncJournal journal, SessionState local, JsonArray incoming,
        bool replacing, DateTimeOffset now, SpaceState? emptySpace, SpaceAccessAuthority? access, IIdSource ids,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        var seconds = StoredSessionCodec.Seconds(now);
        var next = journal;
        if (!replacing && local.DisposableSeedMarker is null)
            next = next.Stage(StoredSessionCodec.Encode(local), SyncDeletionReason.Superseded, seconds, removals);
        next = replacing ? next.Replace(incoming) : next.Merge(incoming);
        var records = NativeSyncEvaluator.Reconcile(next.Records).Select(record => SyncSessionRecord.Read(record!.AsObject())).ToArray();
        // Only accepted explicit Space tombstones authorize erasing a local
        // profile. Cleanup remains pending until that device acknowledges it.
        var pending = local.SpaceDeletions.ToList();
        var pendingIds = pending.Select(deletion => deletion.SpaceId).ToHashSet();
        foreach (var record in records.Where(record => record.Kind == SyncRecordKind.Space && record.Tombstone?.Reason.IsExplicit == true)) {
            var space = local.Spaces.FirstOrDefault(space => space.Id == record.Id);
            if (space is not null && pendingIds.Add(space.Id)) pending.Add(new(Guid.NewGuid(), space.Id, space.ProfileId));
        }
        local = local with { SpaceDeletions = pending };
        var raw = replacing && incoming.Count == 0 ? local with { Spaces = [], DisposableSeedMarker = null }
            : NativeSyncMaterializer.Materialize(local, NativeSyncProjection.Preferences(journal.Preferences), records, now, access);
        var repaired = NativeSessionMaintenance.Repair(raw, now, emptySpace, ids, out var origins);
        repaired = NativeSessionMaintenance.Retain(repaired, now, out var removed);
        if (pending.Count > 0) {
            var spaces = repaired.Spaces.ToList();
            foreach (var intent in pending) {
                var original = local.Spaces.Single(space => space.Id == intent.SpaceId);
                int index = spaces.FindIndex(space => space.Id == intent.SpaceId);
                if (index < 0) spaces.Add(original);
                else spaces[index] = original;
            }
            repaired = repaired with { Spaces = spaces, SpaceDeletions = pending };
        }
        repaired = repaired with { AppPreferences = local.AppPreferences };
        if (!replacing || removed)
            next = next.Stage(StoredSessionCodec.Encode(repaired), removed ? SyncDeletionReason.Retention : SyncDeletionReason.Superseded, seconds);
        return new(next, repaired, origins);
    }

    #endregion

}
