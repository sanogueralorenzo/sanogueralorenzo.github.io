using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Records the cloud transport sent, read from their CloudKit fields into the
/// journal's form and checked before any of them reaches the journal or the
/// session. A record no client of this build's schema reads, or one a newer
/// build wrote for a schema this build does not know, is left out and counted
/// in the receipt, as the Apple clients skip one. A batch that breaks a rule no
/// single record carries is refused whole with `InvalidSyncRecords`.
internal sealed class IncomingSyncRecords {
    #region Variables

    /// Each readable record as the journal holds it, in the order they arrived.
    private readonly IReadOnlyList<JsonObject> nodes;

    /// Each readable record's Space, by its name in the journal, for the kinds
    /// that never move between Spaces.
    private readonly IReadOnlyDictionary<string, Guid> spaces;

    /// The first record left out, which a refusal of the whole batch names.
    private readonly Guid? firstSkipped;

    /// How many records no client of this build's schema reads.
    public int Unreadable { get; }

    /// How many records a newer build wrote for a schema this build does not know.
    public int FromNewerBuild { get; }

    /// What the transport hears about the records left out: nothing when every
    /// record was read.
    public IReadOnlyList<Change> Receipt => Unreadable + FromNewerBuild == 0 ? [] : [new SyncRecordsSkipped(Unreadable, FromNewerBuild)];

    /// Whether no record was read.
    public bool IsEmpty => nodes.Count == 0;

    #endregion

    #region Constructors

    /// Reads `records`. Throws `Rejected` with `InvalidSyncRecords` for more
    /// records than a journal keeps and for two readable ones that share an
    /// identity.
    public IncomingSyncRecords(IReadOnlyList<SyncRecord> records) {
        if (records.Count > NativeSyncJournal.MaximumRecords) throw Refused(SyncRecordFlaw.TooManyRecords, subject: null);
        var read = new List<JsonObject>(records.Count);
        var names = new HashSet<string>(StringComparer.Ordinal);
        var placed = new Dictionary<string, Guid>(StringComparer.Ordinal);
        foreach (var record in records) {
            if (record.Schema > SyncRecordBody.NewestSchema) {
                FromNewerBuild++;
                firstSkipped ??= record.Id;
                continue;
            }
            if (Node(record) is not { } node) {
                Unreadable++;
                firstSkipped ??= record.Id;
                continue;
            }
            string name = record.Kind.RecordName(record.Id);
            if (!names.Add(name)) throw Refused(SyncRecordFlaw.DuplicateRecord, record.Id);
            if (!record.Kind.MovesBetweenSpaces) placed[name] = record.SpaceId;
            read.Add(node);
        }
        nodes = read;
        spaces = placed;
    }

    #endregion

    #region Actions - Reading

    /// The readable records as a journal request carries them, each a copy.
    public JsonArray Batch() => new([.. nodes.Select(node => (JsonNode?)node.DeepClone())]);

    /// Throws `Rejected` with `InvalidSyncRecords` naming `UnreadablePayload`
    /// unless every record was read.
    public void RequireWhole() {
        if (firstSkipped is { } skipped) throw Refused(SyncRecordFlaw.UnreadablePayload, skipped);
    }

    /// Throws `Rejected` with `InvalidSyncRecords` naming `ChangedSpace` for a
    /// record `journal` holds in another Space than the one it arrived in, of
    /// a kind that never moves between Spaces. A moved tab or archive merges
    /// as any other version of it does.
    public void RequireSameSpaces(NativeSyncJournal journal) {
        foreach (var (name, space) in spaces)
            if (journal.SpaceOf(name) is { } held && held != space) throw Refused(SyncRecordFlaw.ChangedSpace, spaceOfName: name);
    }

    /// `record` as the journal holds it, in the member order and spelling the
    /// Apple clients write: its identity, its Space, its version, then its
    /// payload or its tombstone in the journal's form. Null when no client of
    /// this build's schema reads it.
    private static JsonObject? Node(SyncRecord record) {
        if (record.Schema < 1 || record.Id == Guid.Empty || record.SpaceId == Guid.Empty || record.Version.DeviceId == Guid.Empty) return null;
        JsonObject body;
        try {
            var read = SyncRecordBody.Read(record.Body, record.IsTombstone, SyncPayloadForm.Cloud);
            read.RequireRecord(record.Kind, record.Id, record.SpaceId);
            body = read.Write(SyncPayloadForm.Journal);
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
        var node = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = record.Kind.Name, ["value"] = Spelled(record.Id) },
            ["spaceID"] = new JsonObject { ["rawValue"] = Spelled(record.SpaceId) },
            ["version"] = new JsonObject { ["logicalClock"] = record.Version.Clock, ["deviceID"] = Spelled(record.Version.DeviceId) },
            [record.IsTombstone ? "tombstone" : "payload"] = body
        };
        // Every rule the journal reads a record by, which a record every client
        // reads keeps; one that breaks one is as unreadable here.
        try {
            NativeSyncEvaluator.ValidateRecord(node);
        } catch (BrowserRuleException) {
            return null;
        }
        return node;
    }

    /// An identity as the Apple clients spell it.
    private static string Spelled(Guid id) => id.ToString("D").ToUpperInvariant();

    private static Rejected Refused(SyncRecordFlaw flaw, Guid? subject) => new(new InvalidSyncRecords(flaw, subject));

    private static Rejected Refused(SyncRecordFlaw flaw, string spaceOfName) =>
        Refused(flaw, Guid.Parse(spaceOfName[(spaceOfName.IndexOf(':') + 1)..]));

    #endregion
}
