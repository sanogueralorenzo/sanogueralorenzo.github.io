using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    /// The journal and session merging `records`, records in the journal's
    /// form, into `session`, or replacing it with them, make at `now`.
    private static NativeSyncSessionTransition Transition(NativeSyncJournal journal, JsonNode session, JsonNode records, bool replacing,
        double now) => NativeSyncSessionTransition.Prepare(journal, session.AsObject(), records.AsArray(), replacing, now, emptySpace: null,
        access: null, ids: null);

    [Fact]
    public void SessionRepairIsAtomicAndReidentifiesRuntimeCollisions() {
        var source = SavedSession().Document["session"]!.AsObject();
        source["spaces"]!.AsArray().Add(source["spaces"]![0]!.DeepClone());
        var before = Bytes(source);
        var output = NativeSessionMaintenance.Repair(source, 800000000);
        var result = output["session"]!;
        Assert.Equal(before, Bytes(source));
        Assert.NotEqual(result["spaces"]![0]!["id"]!.ToJsonString(), result["spaces"]![1]!["id"]!.ToJsonString());
        Assert.NotEqual(result["spaces"]![0]!["profile"]!["id"]!.ToJsonString(), result["spaces"]![1]!["profile"]!["id"]!.ToJsonString());
        Assert.NotEqual(result["spaces"]![0]!["tabs"]![0]!["id"]!.ToJsonString(), result["spaces"]![1]!["tabs"]![0]!["id"]!.ToJsonString());
        Assert.Equal(1, output["assets"]!.AsArray().Last()!["spaceIndex"]!.GetValue<int>());
        Assert.True(JsonNode.DeepEquals(result, NativeSessionMaintenance.Repair(result.AsObject(), 800000001)["session"]));
    }

    [Fact]
    public void ASeedOpensRepairedAsTheFileDoesAndEachReidentifiedTabFollowsAsACopy() {
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        // A twin of the first Space that keeps its identity, profile and tab,
        // and whose tab sits in a folder the twin does not hold.
        var twin = document["spaces"]![0]!.DeepClone().AsObject();
        twin["folders"] = new JsonArray();
        document["spaces"]!.AsArray().Add(twin);

        using var app = new CrestApp();
        var changes = app.Send(new OpenWorkspace(WorkspaceKind.Persistent, TestWorkspaces.Seed(document)));
        var opened = Assert.Single(changes.OfType<WorkspaceOpened>());
        var spaces = opened.Session.Spaces;
        Assert.Equal(fixture.Space, spaces[0].Id);
        Assert.Equal(fixture.Tab, spaces[0].Tabs[0].Id);
        Assert.NotEqual(spaces[0].Id, spaces[1].Id);
        Assert.NotEqual(spaces[0].ProfileId, spaces[1].ProfileId);
        var copy = spaces[1].Tabs[0];
        Assert.NotEqual(fixture.Tab, copy.Id);
        Assert.Null(copy.FolderId);
        var copied = Assert.Single(changes.OfType<TabCopied>());
        Assert.Equal(new TabCopied(opened.WorkspaceId, fixture.Tab, copy.Id), copied);
        Assert.True(changes.ToList().IndexOf(opened) < changes.ToList().IndexOf(copied));
    }

    [Fact]
    public void FailedRetentionLeavesEveryCategoryAndTheSourceUnchanged() {
        var source = SavedSession().Document["session"]!.AsObject(); var space = source["spaces"]![0]!;
        space["browsingPreferences"]!["dataRetention"] = new JsonObject { ["history"] = "oneDay", ["archive"] = "oneDay" };
        space["history"] = new JsonArray(new JsonObject {
            ["id"] = Guid.NewGuid().ToString(),
            ["url"] = "https://example.com/old",
            ["title"] = "Old visit",
            ["firstVisitedAt"] = 0.0,
            ["lastVisitedAt"] = 0.0,
            ["visitCount"] = 1
        });
        space["archivedTabs"] = new JsonArray(new JsonObject { ["tab"] = space["tabs"]![0]!.DeepClone(), ["archivedAt"] = "invalid" });
        var before = Bytes(source);
        Assert.Equal(BrowserRule.InvalidSavedState,
            Assert.Throws<BrowserRuleException>(() => NativeSessionMaintenance.Retain(source, 800000000)).Rule);
        Assert.Equal(before, Bytes(source));
        space["archivedTabs"] = new JsonArray();
        var retained = NativeSessionMaintenance.Retain(source, 800000000);
        Assert.True(retained["changed"]!.GetValue<bool>());
        Assert.Empty(retained["session"]!["spaces"]![0]!["history"]!.AsArray());
        Assert.Single(space["history"]!.AsArray());
    }

    [Fact]
    public void PreparedSyncFailureCannotAdvanceTheJournalAfterLocalStaging() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial)); var before = journal.Read().ToArray();
        var space = NativeSyncProjection.Project(session, SyncProjectionPreferences(), [])
            .Single(n => n!["type"]!.GetValue<string>() == "space")!;
        space["value"]!["profileID"] = Guid.NewGuid().ToString("D");
        var incoming = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = "space", ["value"] = fixture.Space.ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space),
            ["payload"] = space.DeepClone(),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") }
        };
        var error = Assert.Throws<SyncRecordsFlawedException>(() =>
            Transition(journal, session.DeepClone(), new JsonArray(incoming), replacing: false, now: 800000000.0));
        Assert.Equal(SyncRecordFlaw.ProfileChanged, error.Flaw);
        Assert.Equal(before, journal.Read());
    }

    [Fact]
    public void ReplacingASeedWithCloudProducesAMatchedNonDisposableSessionAndJournal() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial));
        var staged = journal.Stage(session.DeepClone().AsObject(), SyncDeletionReason.Superseded, 800000000.0);
        var records = JsonNode.Parse(staged.Read())!["records"]!.DeepClone();
        session["disposableSeedMarker"] = Guid.NewGuid().ToString("D");
        var transition = Transition(journal, session.DeepClone(), records, replacing: true, now: 800000000.0);
        var result = transition.Materialization["session"]!.AsObject();
        Assert.Null(result["disposableSeedMarker"]);
        var payloads = NativeSyncProjection.Project(result, SyncProjectionPreferences(),
            JsonNode.Parse(transition.Journal.Read())!["records"]!.AsArray().Select(n => n!.AsObject()));
        Assert.Equal(new[] { "folder", "history", "space", "tab" },
            payloads.Select(p => p!["type"]!.GetValue<string>()).Order(StringComparer.Ordinal));
        Assert.Empty(JsonNode.Parse(transition.Journal.Read())!["pendingRecordIDs"]!.AsArray());
        Assert.NotNull(session["disposableSeedMarker"]);
    }

    [Fact]
    public void CloudReplacementCannotDiscardLocallyAuthorizedCleanup() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["spaceDeletions"] = new JsonArray(new JsonObject {
            ["spaceID"] = session["spaces"]![0]!["id"]!.DeepClone(),
            ["profileID"] = session["spaces"]![0]!["profile"]!["id"]!.DeepClone(),
            ["operationID"] = Guid.NewGuid().ToString("D").ToUpperInvariant()
        });
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        var journal = new NativeSyncJournal(Bytes(initial));
        var transition = Transition(journal, session.DeepClone(), new JsonArray(), replacing: true, now: 800000000.0);
        var result = transition.Materialization["session"]!;
        Assert.True(JsonNode.DeepEquals(session["spaceDeletions"], result["spaceDeletions"]));
        Assert.Equal(2, result["spaces"]!.AsArray().Count);
        var kept = result["spaces"]!.AsArray().Single(s => JsonNode.DeepEquals(s!["id"], session["spaces"]![0]!["id"]));
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0], kept));
        Assert.False(JsonNode.DeepEquals(result["selectedSpaceID"], kept!["id"]));
        var repaired = NativeSessionMaintenance.Repair(result.AsObject(), 800000000.0)["session"]!;
        Assert.True(JsonNode.DeepEquals(result["spaceDeletions"], repaired["spaceDeletions"]));
        var tombstone = new JsonObject {
            ["id"] = new JsonObject { ["kind"] = "space", ["value"] = fixture.Space.ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") },
            ["tombstone"] = new JsonObject { ["reason"] = "explicitDelete", ["deletedAt"] = 800000000.0 }
        };
        var merged = Transition(journal, session.DeepClone(), new JsonArray(tombstone), replacing: false, now: 800000000.0);
        var record = JsonNode.Parse(merged.Journal.Read())!["records"]!.AsArray().Single(r =>
            r!["id"]!["kind"]!.GetValue<string>() == "space" && Guid.Parse(r["id"]!["value"]!.GetValue<string>()) == fixture.Space)!;
        Assert.Equal("explicitDelete", record["tombstone"]!["reason"]!.GetValue<string>());
        Assert.Single(merged.Materialization["session"]!["spaceDeletions"]!.AsArray());
    }
    [Theory]
    [InlineData("merge", "space", "explicitDelete", true)]
    [InlineData("replace", "space", "explicitDelete", true)]
    [InlineData("merge", "space", "retention", false)]
    [InlineData("replace", "space", "superseded", false)]
    [InlineData("merge", "tab", "explicitDelete", false)]
    [InlineData("replace", "absent", "explicitDelete", false)]
    public void OnlyAcceptedExplicitSpaceDeletionAuthorizesLocalCleanup(string operation, string kind, string reason, bool expected) {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        var before = Bytes(session);
        var journal = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()))));
        var incoming = new JsonArray();
        if (kind != "absent") incoming.Add((JsonNode)new JsonObject {
            ["id"] = new JsonObject { ["kind"] = kind, ["value"] = (kind == "space" ? fixture.Space : fixture.Tab).ToString("D") },
            ["spaceID"] = SwiftId(fixture.Space),
            ["version"] = new JsonObject { ["logicalClock"] = 900UL, ["deviceID"] = Guid.NewGuid().ToString("D") },
            ["tombstone"] = new JsonObject { ["reason"] = reason, ["deletedAt"] = 800000000.0 }
        });
        var transition = Transition(journal, session.DeepClone(), incoming, replacing: operation == "replace", now: 800000000.0);
        Assert.Equal(before, Bytes(session));
        var result = transition.Materialization["session"]!;
        Assert.Equal(expected, result["spaceDeletions"] is JsonArray { Count: 1 });
        if (!expected) return;
        var intent = result["spaceDeletions"]![0]!;
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0]!["profile"]!["id"], intent["profileID"]));
        Assert.Equal(2, result["spaces"]!.AsArray().Count); // Keep one usable Space when the last remote Space is deleted.
        var frozen = result["spaces"]!.AsArray().Single(s => JsonNode.DeepEquals(s!["id"], intent["spaceID"]));
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0], frozen));
        Assert.False(JsonNode.DeepEquals(result["selectedSpaceID"], intent["spaceID"]));
        var tombstone = JsonNode.Parse(transition.Journal.Read())!["records"]!.AsArray().Single(r =>
            r!["id"]!["kind"]!.GetValue<string>() == "space" && Guid.Parse(r["id"]!["value"]!.GetValue<string>()) == fixture.Space)!;
        Assert.Equal("explicitDelete", tombstone["tombstone"]!["reason"]!.GetValue<string>());
    }
}
