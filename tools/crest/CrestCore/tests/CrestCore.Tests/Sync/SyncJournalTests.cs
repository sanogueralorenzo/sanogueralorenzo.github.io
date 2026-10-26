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

}
