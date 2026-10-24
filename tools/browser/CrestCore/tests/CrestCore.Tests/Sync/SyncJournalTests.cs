using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonObject JournalDocument(JsonObject record, ulong? clock = null) => new() {
        ["schemaVersion"] = 1,
        ["deviceID"] = Guid.NewGuid().ToString().ToUpperInvariant(),
        ["logicalClock"] = clock ?? 1UL,
        ["preferences"] = new JsonObject { ["savedStructure"] = true, ["currentTabs"] = true, ["historyAndArchive"] = true, ["extensionSettings"] = false },
        ["records"] = new JsonArray(record.DeepClone()),
        ["pendingRecordIDs"] = new JsonArray(record["id"]!.DeepClone())
    };
    /// `journal` after staging `payloads`, everything a session holds that
    /// syncs, with no tab archived and no Space being deleted.
    private static NativeSyncJournal Staging(NativeSyncJournal journal, SyncDeletionReason reason, double now, params JsonNode[] payloads) =>
        journal.Stage(new JsonArray([.. payloads.Select(payload => (JsonNode?)payload.DeepClone())]), new Dictionary<Guid, ArchiveReason>(),
            new HashSet<Guid>(), reason, now);

    [Fact]
    public void UUIDLetterCaseDoesNotCreateEditsButCaseChangesInTitlesStillDo() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        var payload = record["payload"]!["value"]!;
        payload["title"] = "ABCDEFAB-1234-1234-1234-ABCDEFABCDEF";
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var desired = record["payload"]!.DeepClone();
        desired["value"]!["id"]!["rawValue"] = IdForTest(payload["id"]!).ToLowerInvariant();
        desired["value"]!["spaceID"]!["rawValue"] = IdForTest(payload["spaceID"]!).ToLowerInvariant();
        var unchanged = Staging(journal, SyncDeletionReason.Superseded, 100, desired);
        Assert.Equal(1UL, JsonNode.Parse(unchanged.Read())!["logicalClock"]!.GetValue<ulong>());
        desired["value"]!["title"] = payload["title"]!.GetValue<string>().ToLowerInvariant();
        Assert.Equal(2UL, JsonNode.Parse(Staging(unchanged, SyncDeletionReason.Superseded, 100, desired).Read())!["logicalClock"]!.GetValue<ulong>());
        static string IdForTest(JsonNode value) => value["rawValue"]!.GetValue<string>();
    }

    [Fact]
    public void TimestampEncodingDoesNotCreateEditsButDifferentDateValuesStillDo() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        record["payload"]!["value"]!["positionModifiedAt"] = JsonNode.Parse("811615335.98");
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var desired = record["payload"]!.DeepClone();
        desired["value"]!["positionModifiedAt"] = JsonNode.Parse("811615335.98000002");
        var unchanged = Staging(journal, SyncDeletionReason.Superseded, 100, desired);
        Assert.Equal(1UL, JsonNode.Parse(unchanged.Read())!["logicalClock"]!.GetValue<ulong>());
        desired["value"]!["positionModifiedAt"] = Math.BitIncrement(811615335.98);
        Assert.Equal(2UL, JsonNode.Parse(Staging(unchanged, SyncDeletionReason.Superseded, 100, desired).Read())!["logicalClock"]!.GetValue<ulong>());
    }

    [Fact]
    public void RestagingRetainsAdditiveFieldsWithoutRevivingClearedFieldsOrRemovedMembers() {
        var session = SavedSession().Document["session"]!.AsObject();
        var payload = NativeSyncProjection.Project(session, SyncProjectionPreferences(), [])[0]!.AsObject();
        var groupA = new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["customTitle"] = "Clear me", ["futureGroup"] = "a" };
        var groupB = new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["futureGroup"] = "b" };
        var removed = new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["futureGroup"] = "removed" };
        payload["futureEnvelope"] = new JsonArray(true, "opaque", null);
        payload["value"]!["futureSpace"] = ulong.MaxValue;
        payload["value"]!["branding"] = new JsonObject {
            ["futureBranding"] = "kept",
            ["symbolColor"] = new JsonObject { ["red"] = 1.0 },
            ["crest"] = new JsonObject { ["symbol"] = "lion", ["charge"] = new JsonObject { ["kind"] = "system", ["value"] = "star" }, ["futureCrest"] = 4 }
        };
        payload["value"]!["splitGroups"] = new JsonArray(groupA, groupB, removed);
        var record = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = "space", ["value"] = IdForTest(payload["value"]!["id"]!) },
            ["spaceID"] = payload["value"]!["id"]!.DeepClone(),
            ["payload"] = payload.DeepClone(),
            ["version"] = new JsonObject { ["logicalClock"] = 1UL, ["deviceID"] = Guid.NewGuid().ToString() },
            ["futureRecord"] = "kept"
        };
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var desired = payload.DeepClone().AsObject(); desired.Remove("futureEnvelope");
        var value = desired["value"]!.AsObject(); value.Remove("futureSpace"); value["name"] = "Renamed";
        value["branding"] = new JsonObject { ["crest"] = new JsonObject { ["symbol"] = "oak" } };
        value["splitGroups"] = new JsonArray(new JsonObject { ["id"] = groupB["id"]!.DeepClone() }, new JsonObject { ["id"] = groupA["id"]!.DeepClone() });
        var updated = new NativeSyncJournal(Staging(journal, SyncDeletionReason.ExplicitDelete, 100, desired).Read());
        var result = JsonNode.Parse(updated.Read())!["records"]![0]!;
        Assert.Equal("kept", result["futureRecord"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(payload["futureEnvelope"], result["payload"]!["futureEnvelope"]));
        var body = result["payload"]!["value"]!;
        Assert.Equal(ulong.MaxValue, body["futureSpace"]!.GetValue<ulong>());
        Assert.Equal("Renamed", body["name"]!.GetValue<string>());
        Assert.Equal("kept", body["branding"]!["futureBranding"]!.GetValue<string>());
        Assert.Equal(4, body["branding"]!["crest"]!["futureCrest"]!.GetValue<int>());
        Assert.Null(body["branding"]!["symbolColor"]); Assert.Null(body["branding"]!["crest"]!["charge"]);
        Assert.Equal(new[] { "b", "a" }, body["splitGroups"]!.AsArray().Select(g => g!["futureGroup"]!.GetValue<string>()));
        Assert.Null(body["splitGroups"]![1]!["customTitle"]);
        Assert.Equal(2UL, JsonNode.Parse(Staging(updated, SyncDeletionReason.ExplicitDelete, 100, desired).Read())!["logicalClock"]!.GetValue<ulong>());
        var deleted = Staging(updated, SyncDeletionReason.ExplicitDelete, 101);
        Assert.Null(JsonNode.Parse(deleted.Read())!["records"]![0]!["payload"]);
        Assert.Equal("explicitDelete", JsonNode.Parse(deleted.Read())!["records"]![0]!["tombstone"]!["reason"]!.GetValue<string>());
        static string IdForTest(JsonNode value) => value["rawValue"]!.GetValue<string>();
    }

    [Fact]
    public void AdditiveTabFieldsFollowArchiveAndRestore() {
        var tab = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        tab["payload"]!["value"]!["futureTab"] = "retained";
        var document = JournalDocument(tab);
        var journal = new NativeSyncJournal(Bytes(document));
        var knownTab = tab["payload"]!["value"]!.DeepClone().AsObject(); knownTab.Remove("futureTab");
        var archive = new JsonObject {
            ["type"] = "archive",
            ["value"] = new JsonObject {
                ["tab"] = knownTab.DeepClone(),
                ["archivedAt"] = 200.0,
                ["reason"] = "closed"
            }
        };
        var archived = Staging(journal, SyncDeletionReason.Superseded, 200, archive);
        var records = JsonNode.Parse(archived.Read())!["records"]!.AsArray();
        var archivedRecord = records.Single(r => r!["id"]!["kind"]!.GetValue<string>() == "archive")!;
        Assert.Equal("retained", archivedRecord["payload"]!["value"]!["tab"]!["futureTab"]!.GetValue<string>());
        // Restore on another client that received only the archive record.
        var restored = Staging(new NativeSyncJournal(Bytes(JournalDocument(archivedRecord.AsObject()))), SyncDeletionReason.Superseded, 200,
            new JsonObject { ["type"] = "tab", ["value"] = knownTab });
        var restoredTab = JsonNode.Parse(restored.Read())!["records"]!.AsArray().Single(r => r!["id"]!["kind"]!.GetValue<string>() == "tab")!;
        Assert.Equal("retained", restoredTab["payload"]!["value"]!["futureTab"]!.GetValue<string>());
    }

    [Fact]
    public void ASyncComponentAttachesToOneStoredWorkspaceOnly() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var initial = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 9, Guid.NewGuid()))));
        var sync = new NativeSyncAuthority(initial);
        var owner = TestWorkspaces.Session(session);
        owner.AttachSync(sync);
        owner.AttachSync(sync); // A second window shares this family.
        Assert.Throws<InvalidOperationException>(() => TestWorkspaces.Session(session).AttachSync(sync));
        Assert.Throws<InvalidOperationException>(() => TestWorkspaces.Session(session, WorkspaceKind.Private).AttachSync(new(initial)));
    }

    [Fact]
    public void JournalTransitionFailureKeepsOriginalClockPendingIDsAndRecords() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        var document = JournalDocument(record, ulong.MaxValue - 1);
        var journal = new NativeSyncJournal(Bytes(document));
        var before = journal.Read().ToArray();
        var changed = record["payload"]!.DeepClone(); changed["value"]!["title"] = "New title";
        var added = changed.DeepClone(); added["value"]!["id"] = SwiftId(Guid.NewGuid());
        Assert.Equal(BrowserRule.SyncClockExhausted,
            Assert.Throws<BrowserRuleException>(() => Staging(journal, SyncDeletionReason.Superseded, 100, changed, added)).Rule);
        Assert.Equal(before, journal.Read());
    }

    [Fact]
    public void JournalAcknowledgesOnlyExactVersionsAndSnapshotsRemainIndependent() {
        var record = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 9, Guid.NewGuid());
        var document = JournalDocument(record);
        var journal = new NativeSyncJournal(Bytes(document));
        var reference = new SyncRecordReference(SyncRecordKind.Tab, Guid.Parse(record["id"]!["value"]!.GetValue<string>()));
        var device = Guid.Parse(record["version"]!["deviceID"]!.GetValue<string>());
        var stale = journal.Acknowledge([new UploadedRecord(reference, new SyncVersion(8, device))]);
        Assert.Single(JsonNode.Parse(stale.Read())!["pendingRecordIDs"]!.AsArray());
        var accepted = stale.Acknowledge([new UploadedRecord(reference, new SyncVersion(9, device))]);
        Assert.Empty(JsonNode.Parse(accepted.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.Single(JsonNode.Parse(journal.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.Equal(9UL, JsonNode.Parse(accepted.Read())!["logicalClock"]!.GetValue<ulong>());
    }
}
