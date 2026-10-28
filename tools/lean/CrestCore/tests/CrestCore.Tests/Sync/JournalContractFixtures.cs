using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Sessions, records, journals and devices for the sync journal's contract
/// tests: a journal staged, merged and acknowledged as the stager and the
/// transport drive it, and a device that keeps a session and its journal in
/// its file and takes cloud records through its core.
public sealed partial class BrowserContractsTests {
    #region Static Variables

    /// Seconds from 1970 to 2001, the epoch the stored format counts from.
    private const double UnixEpochInReferenceSeconds = 978_307_200;

    #endregion

    #region Types

    /// One device's sync journal, driven as the stager and the transport drive
    /// it: staged from a whole session in the stored format, merged with
    /// records in the journal's form, and acknowledged at the versions it holds.
    private sealed class JournalUnderTest {
        #region Variables

        /// The journal the last transition answered.
        public NativeSyncJournal Journal { get; private set; }

        /// The journal as it is stored.
        public JsonObject Document => JsonNode.Parse(Journal.Read())!.AsObject();

        /// Every record the journal holds, in the order of their names.
        public IReadOnlyList<JsonObject> Records => [.. Document["records"]!.AsArray().Select(record => record!.AsObject())];

        /// The names of the records that wait to upload.
        public IReadOnlySet<string> Pending =>
            Document["pendingRecordIDs"]!.AsArray().Select(id => RecordName(id!)).ToHashSet(StringComparer.Ordinal);

        public ulong Clock => Document["logicalClock"]!.GetValue<ulong>();

        #endregion

        #region Constructors

        /// A journal of `device` that has staged nothing, syncing the categories
        /// named.
        public JournalUnderTest(Guid device, bool savedStructure = true, bool currentTabs = true, bool historyAndArchive = true) =>
            Journal = new(Bytes(new JsonObject {
                ["schemaVersion"] = 1,
                ["deviceID"] = device.ToString("D").ToUpperInvariant(),
                ["logicalClock"] = 0,
                ["preferences"] = new JsonObject {
                    ["savedStructure"] = savedStructure,
                    ["currentTabs"] = currentTabs,
                    ["historyAndArchive"] = historyAndArchive,
                    ["extensionSettings"] = true
                },
                ["records"] = new JsonArray(),
                ["pendingRecordIDs"] = new JsonArray()
            }));

        public JournalUnderTest(NativeSyncJournal journal) => Journal = journal;

        #endregion

        #region Actions - Transitions

        /// Stages `session` as the core writes it, `at` seconds after 1970,
        /// deleting what it no longer holds, where that authorizes a deletion,
        /// for `reason`, an explicit deletion unless named.
        public void Stage(JsonObject session, SyncDeletionReason? reason = null, double at = 100) =>
            Journal = Journal.Stage(Canonical(session), reason ?? SyncDeletionReason.ExplicitDelete, At(at));

        /// Merges `records`, in the journal's form, as they arrived from the cloud.
        public void Merge(IEnumerable<JsonObject> records) =>
            Journal = Journal.Merge(new JsonArray([.. records.Select(record => (JsonNode?)record.DeepClone())]));

        public void Merge(params JsonObject[] records) => Merge(records.AsEnumerable());

        /// Rebases above the cloud's `records` from `session`, `at` seconds after
        /// 1970, as the person's choice of this device's copy does.
        public void Overwrite(JsonObject session, IEnumerable<JsonObject> records, double at) =>
            Journal = Journal.Overwrite(Canonical(session),
                new JsonArray([.. records.Select(record => (JsonNode?)record.DeepClone())]), At(at));

        /// The cloud saved every record that waits to upload, at the version the
        /// journal holds it at.
        public void MarkUploaded() => Acknowledge([.. Pending.Select(name => (name, Version(name)))]);

        /// The cloud saved the record `name` names at `version`.
        public void MarkUploaded(string name, JsonNode version) => Acknowledge([(name, version)]);

        private void Acknowledge(IReadOnlyList<(string Name, JsonNode Version)> uploads) =>
            Journal = Journal.Acknowledge([.. uploads.Select(upload => new UploadedRecord(Reference(upload.Name), SyncVersionOf(upload.Version)))]);

        #endregion

        #region Actions - Reading

        /// The session this journal's records make of `local`, a session in the
        /// stored format, repaired, as the device that holds `local` shows it.
        public JsonObject Materialize(JsonObject local) {
            var now = At(1_000_000);
            var records = NativeSyncEvaluator.Reconcile(Journal.Records).Select(record => record!.AsObject()).ToArray();
            var session = NativeSyncMaterializer.Materialize(Canonical(local), Journal.Preferences, records, now);
            return NativeSessionMaintenance.Repair(session, now, ids: new TestIds())["session"]!.AsObject();
        }

        /// The record of `kind` with identity `id`, or null when the journal
        /// holds none.
        public JsonObject? Record(SyncRecordKind kind, Guid id) => Records.SingleOrDefault(record => RecordName(record["id"]!) == Name(kind, id));

        /// The payload value of the record of `kind` with identity `id`, or null
        /// when it is a tombstone or absent.
        public JsonObject? Value(SyncRecordKind kind, Guid id) => Record(kind, id)?["payload"]?["value"]?.AsObject();

        /// Every payload value of `kind`.
        public IReadOnlyList<JsonObject> Values(SyncRecordKind kind) => [.. Records
            .Where(record => record["id"]!["kind"]!.GetValue<string>() == kind.Name && record["payload"] is not null)
            .Select(record => record["payload"]!["value"]!.AsObject())];

        /// The version the journal holds the record `name` names at.
        public JsonNode Version(string name) => Records.Single(record => RecordName(record["id"]!) == name)["version"]!.DeepClone();

        #endregion
    }

    /// A device whose file holds a session and its journal, opened as a launch
    /// opens it, which takes cloud records through its core as the transport
    /// does.
    private sealed class SyncingDevice : IDisposable {
        #region Variables

        private readonly StorageDirectory directory = new();
        private readonly StoredSync stored;

        /// The session the device holds, in the stored format.
        public JsonObject Session => StoredSessionCodec.Encode(stored.Session.Current);

        /// The journal the device's core accepted last.
        public JournalUnderTest Journal => new(stored.Sync.Snapshot);

        #endregion

        #region Constructors

        /// A device whose file holds `session` and `journal`.
        public SyncingDevice(JsonObject session, JournalUnderTest journal) =>
            stored = StoredSyncing(directory, new JsonObject { ["session"] = Canonical(session) }, journal: journal.Document);

        /// A device whose file holds `session`, which its journal from `device`
        /// staged `at` seconds after 1970.
        public SyncingDevice(JsonObject session, Guid device, double at = 100) : this(session, Staged(session, device, at)) { }

        #endregion

        #region Actions - Cloud records

        /// Merges `records` from the cloud and answers the session the device
        /// holds then.
        public JsonObject Merge(IEnumerable<JsonObject> records) {
            stored.App.Send(new MergeSyncRecords([.. records.Select(Cloud)]));
            stored.App.Drain();
            return Session;
        }

        public JsonObject Merge(params JsonObject[] records) => Merge(records.AsEnumerable());

        /// Replaces the session with what the cloud holds and answers the
        /// session the device holds then.
        public JsonObject Replace(IEnumerable<JsonObject> records) {
            stored.App.Send(new ReplaceWithCloudRecords([.. records.Select(Cloud)]));
            stored.App.Drain();
            return Session;
        }

        /// Rebases the journal above what the cloud holds.
        public void Overwrite(IEnumerable<JsonObject> records) {
            stored.App.Send(new OverwriteCloud([.. records.Select(Cloud)]));
            stored.App.Drain();
        }

        /// The cloud saved every record that waits to upload, at the version
        /// the journal holds it at.
        public void MarkUploaded() {
            var journal = Journal;
            stored.App.Send(new AcknowledgeUploads([.. journal.Pending.Select(name =>
                new UploadedRecord(Reference(name), SyncVersionOf(journal.Version(name))))]));
            stored.App.Drain();
        }

        public void Dispose() {
            stored.Dispose();
            directory.Dispose();
        }

        private static JournalUnderTest Staged(JsonObject session, Guid device, double at) {
            var journal = new JournalUnderTest(device);
            journal.Stage(session, at: at);
            return journal;
        }

        #endregion
    }

    #endregion

    #region Actions - Names and dates

    /// A date `seconds` after 1970, in the stored format's seconds since 2001.
    private static double At(double seconds) => seconds - UnixEpochInReferenceSeconds;

    /// The identity numbered `value`.
    private static Guid Fixed(int value) => Guid.Parse($"00000000-0000-0000-0000-{value:x12}");

    /// A record's name in the journal.
    private static string Name(SyncRecordKind kind, Guid id) => kind.Name + ":" + id.ToString("D");

    /// The name of the record a journal identity `{kind, value}` names.
    private static string RecordName(JsonNode id) =>
        id["kind"]!.GetValue<string>() + ":" + Guid.Parse(id["value"]!.GetValue<string>()).ToString("D");

    private static SyncRecordReference Reference(string name) {
        int colon = name.IndexOf(':');
        return new(SyncRecordKind.Named(name[..colon])!, Guid.Parse(name[(colon + 1)..]));
    }

    /// The version a journal record's `{logicalClock, deviceID}` spells.
    private static SyncVersion SyncVersionOf(JsonNode version) =>
        new(version["logicalClock"]!.GetValue<ulong>(), Guid.Parse(version["deviceID"]!.GetValue<string>()));

    /// `session` as the core writes a session it holds.
    private static JsonObject Canonical(JsonObject session) => StoredSessionCodec.Encode(StoredSessionCodec.DecodeSession(session));

    /// `record`, in the journal's form, as the cloud transport carries it: its
    /// body in the CloudKit form, at the schema it needs.
    private static SyncRecord Cloud(JsonObject record) {
        var tombstone = record["tombstone"];
        var version = record["version"]!;
        var body = SyncRecordBody.Read(tombstone ?? record["payload"], tombstone is not null, SyncPayloadForm.Journal);
        return new(SyncRecordKind.Named(record["id"]!["kind"]!.GetValue<string>())!, Guid.Parse(record["id"]!["value"]!.GetValue<string>()),
            StoredSessionCodec.Identity(record["spaceID"]), SyncVersionOf(version), body.Schema, body.Bytes(SyncPayloadForm.Cloud),
            tombstone is not null);
    }

    #endregion

    #region Actions - Sessions

    /// A session in the stored format holding `spaces`.
    private static JsonObject SessionOf(params JsonObject[] spaces) => new() {
        ["spaces"] = new JsonArray([.. spaces.Select(space => (JsonNode?)space.DeepClone())])
    };

    /// A Space in the stored format.
    private static JsonObject SpaceOf(Guid id, Guid profile, string name = "Test", string symbol = "sparkles", string accent = "indigo",
        IEnumerable<JsonObject>? tabs = null, IEnumerable<JsonObject>? folders = null) => new() {
            ["id"] = SwiftId(id),
            ["profile"] = new JsonObject { ["id"] = profile.ToString("D").ToUpperInvariant() },
            ["name"] = name,
            ["symbol"] = symbol,
            ["accent"] = accent,
            ["folders"] = new JsonArray([.. (folders ?? []).Select(folder => (JsonNode?)folder)]),
            ["tabs"] = new JsonArray([.. (tabs ?? []).Select(tab => (JsonNode?)tab)]),
            ["splitGroups"] = new JsonArray(),
            ["archivedTabs"] = new JsonArray(),
            ["history"] = new JsonArray()
        };

    /// A tab in the stored format, active `activated` seconds after 1970.
    private static JsonObject TabOf(Guid id, string title = "Example", string? url = "https://example.com", string symbol = "globe",
        string placement = "current", Guid? folder = null, Guid? split = null, double activated = 100, double? positioned = null) {
        var tab = new JsonObject { ["id"] = SwiftId(id), ["title"] = title, ["symbol"] = symbol, ["placement"] = placement };
        if (url is not null) tab["url"] = url;
        if (folder is { } parent) tab["folderID"] = SwiftId(parent);
        if (split is { } group) tab["splitGroupID"] = SwiftId(group);
        tab["lastActivatedAt"] = At(activated);
        if (positioned is { } moved) tab["positionModifiedAt"] = At(moved);
        return tab;
    }

    /// A native view's tab in the stored format.
    private static JsonObject NativeTabOf(Guid id, string kind, string title, string placement = "current") => new() {
        ["id"] = SwiftId(id),
        ["title"] = title,
        ["nativeContent"] = new JsonObject { ["kind"] = kind },
        ["symbol"] = "gearshape",
        ["placement"] = placement,
        ["lastActivatedAt"] = At(100)
    };

    /// A folder in the stored format.
    private static JsonObject FolderOf(Guid id, string title, string symbol = "folder", Guid? parent = null, string location = "saved") {
        var folder = new JsonObject { ["id"] = SwiftId(id), ["title"] = title, ["symbol"] = symbol, ["location"] = location };
        if (parent is { } container) folder["parentID"] = SwiftId(container);
        return folder;
    }

    /// `tab` archived `at` seconds after 1970 for the stored `reason`, a
    /// deletion when `origin` names where it was deleted.
    private static JsonObject ArchivedOf(JsonObject tab, double at, string reason = "closed", string? origin = null) {
        var archived = new JsonObject { ["tab"] = tab.DeepClone(), ["archivedAt"] = At(at), ["reason"] = reason };
        if (origin is not null) archived["deletionOrigin"] = origin;
        return archived;
    }

    /// A visit in the stored format.
    private static JsonObject VisitOf(Guid id, string path, double first = 10, double last = 20, int count = 1) => new() {
        ["id"] = id.ToString("D").ToUpperInvariant(),
        ["url"] = "https://example.com/" + path,
        ["title"] = path,
        ["firstVisitedAt"] = At(first),
        ["lastVisitedAt"] = At(last),
        ["visitCount"] = count
    };

    /// A session of one Space with one current web tab, identities and dates
    /// fixed unless named.
    private static JsonObject OneSpaceSession(Guid? space = null, Guid? profile = null, Guid? tab = null, double activated = 100) =>
        SessionOf(SpaceOf(space ?? Fixed(100), profile ?? Fixed(101), tabs: [TabOf(tab ?? Fixed(102), activated: activated)]));

    /// A session of one Space with `count` current web tabs in order.
    private static JsonObject CurrentTabSession(int count) => SessionOf(SpaceOf(Fixed(700), Fixed(799), "Ordered", "list.number",
        tabs: Enumerable.Range(0, count).Select(index =>
            TabOf(Fixed(701 + index), $"Tab {index}", $"https://example.com/{index}", activated: 100 + index))));

    /// A session of one Space whose current tabs carry the memberships named,
    /// in order.
    private static JsonObject SplitSession(IReadOnlyList<Guid?> memberships, Guid? space = null, double? positioned = null) =>
        SessionOf(SpaceOf(space ?? Fixed(1_100), Fixed(1_119), "Split", "rectangle.split.2x1",
            tabs: memberships.Select((group, index) => TabOf(Fixed(1_101 + index), $"Split {index}", $"https://example.com/split/{index}",
                split: group, activated: 100 + index, positioned: positioned))));

    /// The first Space of `session`.
    private static JsonObject FirstSpace(JsonObject session) => session["spaces"]![0]!.AsObject();

    /// The Space of `session` with identity `id`, or null.
    private static JsonObject? SpaceIn(JsonObject session, Guid id) =>
        session["spaces"]!.AsArray().Select(space => space!.AsObject()).SingleOrDefault(space => SpaceId(space) == id);

    /// The identities of `items`, each a stored record with an `id`.
    private static Guid[] Ids(JsonNode? items) => [.. (items?.AsArray() ?? []).Select(item => StoredSessionCodec.Identity(item!["id"]))];

    /// The identities of the tabs `archive` holds.
    private static Guid[] ArchivedIds(JsonNode? archive) =>
        [.. (archive?.AsArray() ?? []).Select(item => StoredSessionCodec.Identity(item!["tab"]!["id"]))];

    #endregion

    #region Actions - Records

    /// A record in the journal's form, as a device `device` wrote `payload`, a
    /// value of `kind`, at `clock`.
    private static JsonObject SavedRecord(SyncRecordKind kind, JsonObject value, ulong clock, Guid device) {
        var identity = kind == SyncRecordKind.Archive ? value["tab"]! : value;
        var id = StoredSessionCodec.Identity(identity["id"]);
        var space = kind == SyncRecordKind.Space ? id : StoredSessionCodec.Identity(identity["spaceID"]);
        return new() {
            ["id"] = new JsonObject { ["kind"] = kind.Name, ["value"] = id.ToString("D").ToUpperInvariant() },
            ["spaceID"] = SwiftId(space),
            ["version"] = new JsonObject { ["logicalClock"] = clock, ["deviceID"] = device.ToString("D").ToUpperInvariant() },
            ["payload"] = new JsonObject { ["type"] = kind.Name, ["value"] = value.DeepClone() }
        };
    }

    /// A tombstone in the journal's form.
    private static JsonObject TombstoneRecord(SyncRecordKind kind, Guid id, Guid space, ulong clock, Guid device,
        SyncDeletionReason reason, double deletedAt) => new() {
            ["id"] = new JsonObject { ["kind"] = kind.Name, ["value"] = id.ToString("D").ToUpperInvariant() },
            ["spaceID"] = SwiftId(space),
            ["version"] = new JsonObject { ["logicalClock"] = clock, ["deviceID"] = device.ToString("D").ToUpperInvariant() },
            ["tombstone"] = new JsonObject { ["reason"] = reason.Name, ["deletedAt"] = At(deletedAt) }
        };

    /// A Space payload value of the first Space of `session`, as a device that
    /// synced it wrote it.
    private static JsonObject SpaceValue(JsonObject space, string orderToken = "a") => new() {
        ["id"] = space["id"]!.DeepClone(),
        ["profileID"] = space["profile"]!["id"]!.DeepClone(),
        ["name"] = space["name"]!.DeepClone(),
        ["symbol"] = space["symbol"]!.DeepClone(),
        ["accent"] = space["accent"]!.DeepClone(),
        ["orderToken"] = orderToken
    };

    /// A tab payload value of `tab`, a tab in the stored format, in `space`.
    private static JsonObject TabValue(JsonObject tab, Guid space, string orderToken = "a") {
        var value = new JsonObject {
            ["id"] = tab["id"]!.DeepClone(),
            ["spaceID"] = SwiftId(space),
            ["title"] = tab["title"]!.DeepClone(),
            ["symbol"] = tab["symbol"]!.DeepClone(),
            ["placement"] = tab["placement"]!.DeepClone(),
            ["orderToken"] = orderToken,
            ["lastActivatedAt"] = tab["lastActivatedAt"]!.DeepClone()
        };
        foreach (string field in new[] { "url", "folderID", "positionModifiedAt" })
            if (tab[field] is { } member) value[field] = member.DeepClone();
        return value;
    }

    /// `record` with its payload value edited by `edit`, written at `clock` by `device`.
    private static JsonObject Edited(JsonObject record, ulong clock, Guid device, Action<JsonObject> edit) {
        var copy = record.DeepClone().AsObject();
        edit(copy["payload"]!["value"]!.AsObject());
        copy["version"] = new JsonObject { ["logicalClock"] = clock, ["deviceID"] = device.ToString("D").ToUpperInvariant() };
        return copy;
    }

    /// The date a record member holds, in seconds after 1970.
    private static double Unix(JsonNode? date) => date!.GetValue<double>() + UnixEpochInReferenceSeconds;

    #endregion
}
