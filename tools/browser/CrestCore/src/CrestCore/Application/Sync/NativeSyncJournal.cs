using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Immutable sync state. Copies share records until a semantic transition
/// replaces them; failed transitions never publish clocks, records or pending IDs.
public sealed class NativeSyncJournal {
    #region Variables

    public const int MaximumBytes = 64 * 1024 * 1024;
    public const int MaximumRecords = 250_000;
    private readonly JsonObject metadata;
    private readonly Dictionary<string, JsonObject> records;
    private readonly HashSet<string> pending;
    private readonly Lazy<byte[]> encoded;
    internal IEnumerable<JsonObject> Records => records.Values;
    internal JsonNode Preferences => metadata["preferences"]!.DeepClone();
    /// How many records wait to upload.
    internal int PendingCount => pending.Count;
    /// How many records the journal holds, tombstones included.
    internal int RecordCount => records.Count;

    #endregion

    #region Constructors

    public NativeSyncJournal(ReadOnlySpan<byte> bytes) : this(Parse(bytes)) { }

    /// The journal `source`, a stored journal parsed once, which it takes
    /// over: nothing else may hold it.
    internal NativeSyncJournal(JsonObject source) {
        if (SyncJson.Int(source["schemaVersion"]!) != 1) throw new BrowserRuleException(BrowserRule.VersionMismatch);
        // Every member but the records, which the journal keeps by name.
        metadata = new JsonObject(source.Where(member => member.Key is not ("records" or "pendingRecordIDs"))
            .Select(member => KeyValuePair.Create(member.Key, member.Value?.DeepClone())));
        _ = Id(metadata["deviceID"]);
        records = RecordMap(source["records"]!.AsArray());
        pending = source["pendingRecordIDs"]!.AsArray().Select(n => Name(n!)).ToHashSet(StringComparer.Ordinal);
        if (!pending.IsSubsetOf(records.Keys)) throw new BrowserRuleException(BrowserRule.InvalidSyncPending);
        ulong clock = SyncJson.ULong(metadata["logicalClock"]!);
        foreach (var record in records.Values) clock = Math.Max(clock, Clock(record));
        metadata["logicalClock"] = clock;
        encoded = new(Encode, true);
    }

    private NativeSyncJournal(JsonObject metadata, Dictionary<string, JsonObject> records, HashSet<string> pending) { this.metadata = metadata; this.records = records; this.pending = pending; encoded = new(Encode, true); }

    /// The journal of a device that has staged nothing yet: no records, the
    /// clock at zero, and every record category synced.
    public static NativeSyncJournal Fresh(Guid deviceId) => new(Encoding.UTF8.GetBytes(new JsonObject {
        ["schemaVersion"] = 1,
        ["deviceID"] = deviceId.ToString("D").ToUpperInvariant(),
        ["logicalClock"] = 0,
        ["preferences"] = new JsonObject {
            ["savedStructure"] = true,
            ["currentTabs"] = true,
            ["historyAndArchive"] = true,
            ["extensionSettings"] = true
        },
        ["records"] = new JsonArray(),
        ["pendingRecordIDs"] = new JsonArray()
    }.ToJsonString()));

    #endregion

    #region Actions - Decoding

    private static JsonObject Parse(ReadOnlySpan<byte> bytes) {
        if (bytes.Length is 0 or > MaximumBytes) throw new BrowserRuleException(BrowserRule.SyncSizeLimit);
        return JsonNode.Parse(bytes, documentOptions: new() { MaxDepth = 64 })!.AsObject();
    }

    private static Guid Id(JsonNode? node) => SyncJson.Identity(node);

    private static string Kind(JsonNode record) => record["id"]!["kind"]!.GetValue<string>();

    private static string Name(JsonNode id) => id["kind"]!.GetValue<string>() + ":" + Id(id["value"]).ToString("D");

    private static SyncVersion Version(JsonNode record) {
        var version = record["version"]!;
        return new(SyncJson.ULong(version["logicalClock"]!), Id(version["deviceID"]));
    }

    private static SyncRecordReference Reference(JsonNode record) =>
        new(SyncRecordKind.Named(Kind(record)) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncKind),
            Id(record["id"]!["value"]));

    private static ulong Clock(JsonNode record) => SyncJson.ULong(record["version"]!["logicalClock"]!);

    private static JsonObject? Payload(JsonNode record) => record["payload"] as JsonObject;

    private static JsonObject Value(JsonNode payload) => payload["value"]!.AsObject();

    /// An archive reason this build does not know counts as a close, as the
    /// stored session reads it.
    private static ArchiveReason Known(string name) => ArchiveReason.Named(name) ?? ArchiveReason.Closed;

    private static JsonObject PayloadId(JsonObject payload) {
        var type = SyncPayloadType.Of(payload);
        return new() { ["kind"] = type.Kind.Name, ["value"] = Id(type.Subject(Value(payload))["id"]).ToString("D").ToUpperInvariant() };
    }

    private static JsonNode PayloadSpace(JsonObject payload) => SyncPayloadType.Of(payload).SpaceIdentity(Value(payload));

    #endregion

    #region Actions - Journal updates

    /// The journal of a restored checkpoint, owned by a new device identity so
    /// it never reissues a version it issued after the checkpoint was taken.
    /// Its records, clock and pending uploads are unchanged.
    public NativeSyncJournal Recovered(Guid deviceId) {
        if (deviceId == Id(metadata["deviceID"])) throw new ArgumentException("A recovered journal takes a new device identity.", nameof(deviceId));
        var fields = metadata.DeepClone().AsObject();
        fields["deviceID"] = deviceId.ToString("D").ToUpperInvariant();
        return new(fields, new(records, StringComparer.Ordinal), new(pending, StringComparer.Ordinal));
    }

    /// The Space the record `name` names belongs to here, or null when the
    /// journal holds no such record.
    internal Guid? SpaceOf(string name) => records.TryGetValue(name, out var record) ? Id(record["spaceID"]) : null;

    /// The journal after staging `session`, a whole session in the stored
    /// format that nothing else holds, under this journal's preferences.
    /// Records it no longer holds are deleted, where their absence authorizes a
    /// deletion, for the reason `removals` names for them by record name, else
    /// for `reason`; `now` in seconds since 2001 dates the tombstones.
    internal NativeSyncJournal Stage(JsonObject session, SyncDeletionReason reason, double now,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        var archiveReasons = NativeSyncProjection.Items(session, "spaces")
            .SelectMany(space => NativeSyncProjection.Items(space!, StoredSessionCodec.Key.ArchivedTabs))
            .ToDictionary(archived => Id(archived!["tab"]!["id"]), archived => Known(NativeSyncProjection.ArchiveReasonName(archived!)));
        return Stage(NativeSyncProjection.Project(session, Preferences, records.Values), archiveReasons, Cleaning(session), reason, now,
            removals);
    }

    /// The journal after staging `payloads`, everything a session holds that
    /// syncs, as `Stage(session:)` does: `archiveReasons` says why each archived
    /// tab was archived, and a record of a Space in `cleaning`, whose deletion
    /// is under way on this device, is left as it is.
    internal NativeSyncJournal Stage(JsonArray payloads, IReadOnlyDictionary<Guid, ArchiveReason> archiveReasons,
        IReadOnlySet<Guid> cleaning, SyncDeletionReason reason, double now, IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        var draft = new Draft(this);
        var desired = draft.Desired(payloads, cleaning);
        // Parent evidence is from the accepted journal before staging.
        var spaces = records.Values.Where(r => Kind(r) == SyncRecordKind.Space.Name).Select(r => Id(r["spaceID"])).ToHashSet();
        var folders = records.Values.Where(r => Kind(r) == SyncRecordKind.Folder.Name).ToDictionary(r => Id(r["id"]!["value"]));
        foreach (var (name, payload) in desired.OrderBy(p => p.Key, StringComparer.Ordinal)) {
            if (draft.Records.TryGetValue(name, out var existing) && NativeSyncEvaluator.Equivalent(Payload(existing), payload)) continue;
            draft.Records[name] = draft.Save(payload);
            draft.Pending.Add(name);
        }
        foreach (var (name, record) in draft.Records.ToArray()) {
            if (cleaning.Contains(Id(record["spaceID"]))) continue;
            if (Payload(record) is not { } payload) continue;
            var type = SyncPayloadType.Of(payload);
            var value = Value(payload);
            if (!type.SyncsUnder(Preferences, value) || desired.ContainsKey(name)) continue;
            SyncDeletionReason? deletion;
            if (!type.IsPortable(value)) deletion = SyncDeletionReason.Superseded;
            else {
                if (!spaces.Contains(Id(record["spaceID"])) || !AncestryArrived(type.ParentFolder(value), folders)) continue;
                deletion = type.DeletionReason(value, archiveReasons.GetValueOrDefault(Id(record["id"]!["value"])),
                    desired.ContainsKey(SyncRecordKind.Space.RecordName(Id(record["spaceID"]))), removals?.GetValueOrDefault(name) ?? reason);
            }
            if (deletion is null) continue;
            draft.Records[name] = draft.Delete(record, deletion, now);
            draft.Pending.Add(name);
        }
        return draft.Finish();
    }

    /// The journal after merging `incoming`, records in the journal's form:
    /// a record it lacks is taken, and one it holds resolves with the local
    /// copy. A resolution that is neither side's waits to upload.
    internal NativeSyncJournal Merge(JsonArray incoming) {
        var draft = new Draft(this);
        foreach (var (name, remote) in draft.Arrive(incoming)) {
            if (!draft.Records.TryGetValue(name, out var local)) {
                draft.Records[name] = remote;
                continue;
            }
            var resolved = NativeSyncEvaluator.Resolve(local, remote);
            draft.Records[name] = resolved;
            // An acknowledged local winner does not become pending merely
            // because a fetch races an older server version.
            if (!NativeSyncEvaluator.Equivalent(resolved, local) && !NativeSyncEvaluator.Equivalent(resolved, remote)) draft.Pending.Add(name);
        }
        return draft.Finish();
    }

    /// The journal that holds exactly `incoming`, records in the journal's
    /// form, with nothing waiting to upload.
    internal NativeSyncJournal Replace(JsonArray incoming) {
        var draft = new Draft(this);
        draft.Records = draft.Arrive(incoming);
        draft.Pending.Clear();
        return draft.Finish();
    }

    /// The journal after rebasing above `cloud`, records the cloud holds, from
    /// `session`, a whole session in the stored format that nothing else holds:
    /// each record is written above the cloud's and waits to upload. A record
    /// the session no longer holds is deleted for the reason `removals` names
    /// for it, else as superseded; `now` in seconds since 2001 dates the
    /// tombstones.
    internal NativeSyncJournal Overwrite(JsonObject session, JsonArray cloud, double now,
        IReadOnlyDictionary<string, SyncDeletionReason>? removals = null) {
        var draft = new Draft(this);
        foreach (var (name, remote) in draft.Arrive(cloud)) draft.Records[name] = remote;
        var cleaning = Cleaning(session);
        var desired = draft.Desired(NativeSyncProjection.Project(session, Preferences, records.Values), cleaning);
        draft.Pending.Clear();
        foreach (string name in draft.Records.Keys.Union(desired.Keys).Order(StringComparer.Ordinal).ToArray()) {
            if (draft.Records.TryGetValue(name, out var held) && cleaning.Contains(Id(held["spaceID"]))) continue;
            if (desired.TryGetValue(name, out var payload)) draft.Records[name] = draft.Save(payload);
            else {
                if (Payload(draft.Records[name]) is { } old && !SyncPayloadType.Of(old).SyncsUnder(Preferences, Value(old))) continue;
                draft.Records[name] = draft.Delete(draft.Records[name], removals?.GetValueOrDefault(name) ?? SyncDeletionReason.Superseded, now);
            }
            draft.Pending.Add(name);
        }
        return draft.Finish();
    }

    /// The Spaces `session` is deleting on this device. Pending cleanup is
    /// local recovery state: it neither edits their records nor revives an
    /// incoming deletion of them.
    private static HashSet<Guid> Cleaning(JsonObject session) =>
        (session["spaceDeletions"] as JsonArray ?? []).Select(deletion => Id(deletion!["spaceID"])).ToHashSet();

    /// Whether every folder above `parent`, the folder a record sits in, is
    /// one of `folders` and holds a folder, so its absence is evidence.
    private static bool AncestryArrived(JsonNode? parent, Dictionary<Guid, JsonObject> folders) {
        var next = parent;
        var seen = new HashSet<Guid>();
        while (next is not null) {
            var id = Id(next);
            if (!folders.TryGetValue(id, out var record)) return false;
            if (!seen.Add(id)) return true; // Materialization rejects cycles.
            if (Payload(record) is not { } folder) return false;
            next = Value(folder)["parentID"];
        }
        return true;
    }

    #endregion

    #region Actions - Uploads

    /// The records that wait to upload, in the order of their names.
    internal IReadOnlyList<SyncRecordReference> PendingReferences() =>
        [.. pending.Order(StringComparer.Ordinal).Select(name => Reference(records[name]))];

    /// Whether the journal holds the record `reference` names.
    internal bool Holds(SyncRecordReference reference) => records.ContainsKey(reference.Kind.RecordName(reference.Id));

    /// The record `reference` names as the cloud transport uploads it, its
    /// body in the CloudKit form at the schema it needs, or null when the
    /// journal holds no such record or holds one this device does not send:
    /// one no client reads, or one naming an address it cannot spell as every
    /// client parses it.
    internal SyncRecord? Uploading(SyncRecordReference reference) {
        if (!records.TryGetValue(reference.Kind.RecordName(reference.Id), out var record)) return null;
        var tombstone = record["tombstone"];
        var space = Id(record["spaceID"]);
        try {
            var body = SyncRecordBody.Read(tombstone ?? record["payload"], tombstone is not null, SyncPayloadForm.Journal);
            body.RequireSendable(reference.Kind, reference.Id, space);
            return new(reference.Kind, reference.Id, space, Version(record), body.Schema, body.Bytes(SyncPayloadForm.Cloud), tombstone is not null);
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// The journal once the cloud saved `uploaded`: each record it holds at
    /// exactly the version the cloud saved no longer waits to upload. A record
    /// written again since, or no longer held, is left as it is. The records
    /// themselves do not change.
    internal NativeSyncJournal Acknowledge(IReadOnlyList<UploadedRecord> uploaded) {
        var queued = new HashSet<string>(pending, StringComparer.Ordinal);
        foreach (var upload in uploaded) {
            string name = upload.Record.Kind.RecordName(upload.Record.Id);
            if (records.TryGetValue(name, out var record) && Version(record) == upload.Version) queued.Remove(name);
        }
        return new(metadata.DeepClone().AsObject(), records, queued);
    }

    /// How this journal compares with `cloud`, every record the cloud holds;
    /// see `CloudContentComparison`. A journal that `holdsNothing` counts as
    /// empty. A cloud record this build cannot read is left out, as the
    /// transport leaves it out of everything else.
    ///
    /// Both sides compare in the CloudKit form. The cloud holds each date as
    /// the seconds since 1970 some client computed from its journal's seconds
    /// since 2001, so converting this device's dates the same way reproduces
    /// the cloud's to the bit when the content is the same: a date this device
    /// uploaded converts with the same arithmetic, and one it downloaded
    /// converts back exactly. Comparing in the journal's form would see the
    /// last bit of a converted date differ where nothing did.
    internal CloudContentComparison Comparing(IReadOnlyList<SyncRecord> cloud, bool holdsNothing) {
        IReadOnlyDictionary<string, JsonObject> device = holdsNothing ? new Dictionary<string, JsonObject>() : records;
        var arrived = new Dictionary<string, (Guid Space, bool IsTombstone, JsonNode Body)>(StringComparer.Ordinal);
        foreach (var record in cloud) {
            if (record.Schema is < 1 or > SyncRecordBody.NewestSchema) continue;
            try {
                var body = SyncRecordBody.Read(record.Body, record.IsTombstone, SyncPayloadForm.Cloud);
                body.RequireRecord(record.Kind, record.Id, record.SpaceId);
                arrived[record.Kind.RecordName(record.Id)] = (record.SpaceId, record.IsTombstone, body.Write(SyncPayloadForm.Cloud));
            } catch (UnreadableSyncPayloadException) {
                // Left out; see the summary.
            }
        }
        bool matches = arrived.Count == device.Count && device.All(held =>
            arrived.TryGetValue(held.Key, out var other) && Id(held.Value["spaceID"]) == other.Space
            && (held.Value["tombstone"] is not null) == other.IsTombstone
            && NativeSyncEvaluator.Equivalent(CloudForm(held.Value), other.Body));
        return new(matches, device.Count, arrived.Count,
            device.Values.Count(record => Kind(record) == SyncRecordKind.Space.Name && Payload(record) is not null),
            arrived.Count(record => record.Key.StartsWith(SyncRecordKind.Space.RecordPrefix, StringComparison.Ordinal) && !record.Value.IsTombstone));
    }

    /// The body of `record`, which this journal holds, in the CloudKit form, or
    /// as the journal holds it when no client reads it.
    private static JsonNode? CloudForm(JsonObject record) {
        var tombstone = record["tombstone"];
        try {
            return SyncRecordBody.Read(tombstone ?? record["payload"], tombstone is not null, SyncPayloadForm.Journal).Write(SyncPayloadForm.Cloud);
        } catch (UnreadableSyncPayloadException) {
            return tombstone ?? record["payload"];
        }
    }

    #endregion

    #region Actions - Encoding

    public byte[] Read() => encoded.Value;

    private byte[] Encode() {
        var value = metadata.DeepClone().AsObject();
        value["records"] = new JsonArray(records.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Value.DeepClone()).ToArray());
        value["pendingRecordIDs"] = new JsonArray(pending.Order(StringComparer.Ordinal).Select(id => records[id]["id"]!.DeepClone()).ToArray());
        var result = Encoding.UTF8.GetBytes(value.ToJsonString());
        if (result.Length > MaximumBytes) throw new BrowserRuleException(BrowserRule.SyncSizeLimit);
        return result;
    }

    #endregion

    #region Mutators

    private static Dictionary<string, JsonObject> RecordMap(JsonArray values) {
        if (values.Count > MaximumRecords) throw new BrowserRuleException(BrowserRule.SyncRecordLimit);
        var result = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        foreach (var value in values) {
            NativeSyncEvaluator.ValidateRecord(value!.AsObject());
            if (!result.TryAdd(Name(value["id"]!), value.AsObject())) throw new BrowserRuleException(BrowserRule.DuplicateSyncRecord);
        }
        return result;
    }

    #endregion

    #region Types

    /// One update of the journal under way: copies of its records, of what
    /// waits to upload and of its clock, which a new journal takes only once
    /// the update completes, so a failed update changes nothing.
    private sealed class Draft {
        #region Variables

        public Dictionary<string, JsonObject> Records;
        public readonly HashSet<string> Pending;
        private readonly JsonObject fields;
        private ulong clock;

        #endregion

        #region Constructors

        public Draft(NativeSyncJournal journal) {
            fields = journal.metadata.DeepClone().AsObject();
            Records = new(journal.records, StringComparer.Ordinal);
            Pending = new(journal.pending, StringComparer.Ordinal);
            clock = SyncJson.ULong(fields["logicalClock"]!);
        }

        #endregion

        #region Actions - Records

        /// Copies of `incoming`, records in the journal's form, by name, with
        /// the clock past every version they carry. Throws when one holds the
        /// last clock, which would leave this journal no version to write a
        /// later edit at.
        public Dictionary<string, JsonObject> Arrive(JsonArray incoming) {
            var arrived = RecordMap(incoming.DeepClone().AsArray());
            foreach (var record in arrived.Values) clock = Math.Max(clock, Clock(record));
            if (clock == ulong.MaxValue) throw new BrowserRuleException(BrowserRule.SyncClockExhausted);
            return arrived;
        }

        /// The payloads by record name that `payloads` stage, each keeping the
        /// additive fields the record it replaces carried, skipping those of a
        /// Space in `cleaning`.
        public Dictionary<string, JsonObject> Desired(JsonArray payloads, IReadOnlySet<Guid> cleaning) {
            var desired = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
            foreach (var node in payloads) {
                var payload = node!.AsObject();
                if (cleaning.Contains(Id(PayloadSpace(payload)))) continue;
                var id = PayloadId(payload);
                Records.TryGetValue(Name(id), out var previous);
                var previousPayload = previous is null ? null : Payload(previous);
                // Closing and restoring a tab changes its record's kind, not the
                // tab: carry its additive fields across.
                var type = SyncPayloadType.Of(payload);
                if (previousPayload is null && type.Counterpart is { } counterpart
                    && Records.TryGetValue(counterpart.Kind.RecordName(Id(id["value"])), out var other) && Payload(other) is { } held) {
                    previousPayload = new JsonObject {
                        ["type"] = type.Kind.Name,
                        ["value"] = type.Holding(counterpart.Subject(Value(held)))
                    };
                }
                payload = NativeSyncCompatibility.Preserve(payload, previousPayload);
                if (!desired.TryAdd(Name(PayloadId(payload)), payload)) throw new BrowserRuleException(BrowserRule.DuplicateSyncRecord);
            }
            if (desired.Count > MaximumRecords) throw new BrowserRuleException(BrowserRule.SyncRecordLimit);
            return desired;
        }

        /// The record `payload` writes at the next version, keeping whatever
        /// else the record it replaces carried.
        public JsonObject Save(JsonObject payload) {
            var id = PayloadId(payload);
            var result = Records.TryGetValue(Name(id), out var previous) ? previous.DeepClone().AsObject() : new JsonObject();
            result["id"] = id;
            result["spaceID"] = PayloadSpace(payload).DeepClone();
            result["payload"] = payload.DeepClone();
            result["version"] = NextVersion();
            result.Remove("tombstone");
            return result;
        }

        /// The tombstone of `previous` at the next version, deleted for
        /// `reason` at `now` in seconds since 2001.
        public JsonObject Delete(JsonObject previous, SyncDeletionReason reason, double now) {
            if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRule.InvalidSyncDate);
            return new() {
                ["id"] = previous["id"]!.DeepClone(),
                ["spaceID"] = previous["spaceID"]!.DeepClone(),
                ["version"] = NextVersion(),
                ["tombstone"] = new JsonObject { ["reason"] = reason.Name, ["deletedAt"] = now }
            };
        }

        /// The journal the update made.
        public NativeSyncJournal Finish() {
            if (Records.Count > MaximumRecords) throw new BrowserRuleException(BrowserRule.SyncRecordLimit);
            fields["logicalClock"] = clock;
            return new(fields, Records, Pending);
        }

        private JsonObject NextVersion() {
            if (clock == ulong.MaxValue) throw new BrowserRuleException(BrowserRule.SyncClockExhausted);
            return new() { ["logicalClock"] = ++clock, ["deviceID"] = fields["deviceID"]!.DeepClone() };
        }

        #endregion
    }

    #endregion
}
