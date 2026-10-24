using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static JsonObject SyncProjectionPreferences(bool saved = true, bool current = true, bool history = true)
        => new() { ["savedStructure"] = saved, ["currentTabs"] = current, ["historyAndArchive"] = history };

    [Theory]
    [InlineData("https://example.com", true)]
    [InlineData("http://localhost:3200", true)]
    [InlineData("crest://extensions", false)]
    [InlineData("chrome://extensions", false)]
    [InlineData("chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html", false)]
    [InlineData("file:///tmp/page.html", false)]
    [InlineData("about:blank", false)]
    [InlineData(null, false)]
    public void OnlyPortableWebContentEntersSharedRecords(string? url, bool expected) {
        Assert.Equal(expected, SyncedAddress.IncludesTab(url, false, null));
        Assert.False(SyncedAddress.IncludesTab(url, true, null));
        Assert.False(SyncedAddress.IncludesTab(url, false, "crest://settings"));
    }

    [Fact]
    public void ProjectionPreservesWireMetadataButExcludesLocalAssetsAndDisabledCategories() {
        var session = SavedSession().Document["session"]!.AsObject(); var space = session["spaces"]![0]!;
        var original = space["tabs"]![0]!;
        original["faviconData"] = "local-image";
        var local = original.DeepClone(); local["id"] = SwiftId(Guid.NewGuid()); local["url"] = "crest://extensions/";
        space["tabs"]!.AsArray().Add(local);
        space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = original["splitGroupID"]!.DeepClone(), ["customTitle"] = "Research" });
        var result = NativeSyncProjection.Project(session, SyncProjectionPreferences(), []);
        var tab = Assert.Single(result, p => p!["type"]!.GetValue<string>() == "tab")!["value"]!;
        Assert.Equal("https://example.com/", tab["savedURL"]!.GetValue<string>());
        Assert.Null(tab["faviconData"]); Assert.Null(tab["faviconURL"]); Assert.Null(tab["iconAccent"]);
        var projectedSpace = result[0]!["value"]!;
        Assert.Null(projectedSpace["credentialPreferences"]);
        Assert.True(JsonNode.DeepEquals(space["branding"], projectedSpace["branding"]));
        Assert.True(JsonNode.DeepEquals(space["browsingPreferences"], projectedSpace["browsingPreferences"]));
        Assert.Single(projectedSpace["splitGroups"]!.AsArray());
        var disabled = NativeSyncProjection.Project(session, SyncProjectionPreferences(false, false, false), []);
        Assert.Single(disabled);
        // Group intent survives turning off tab categories on this device.
        Assert.Single(disabled[0]!["value"]!["splitGroups"]!.AsArray());
        Assert.Equal("local-image", original["faviconData"]!.GetValue<string>());
    }

    [Fact]
    public void ProjectionRetainsPositionsAndClearsArchivedMembershipWithoutChangingLocalAuditReason() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject(); var space = session["spaces"]![0]!;
        var tab = space["tabs"]![0]!; tab.AsObject().Remove("savedURL");
        var record = SyncTabRecord(fixture.Tab, fixture.Space, 10, Guid.NewGuid());
        record["payload"]!["value"]!["orderToken"] = "3fffffffffffffff";
        space["archivedTabs"] = new JsonArray(new JsonObject { ["tab"] = tab.DeepClone(), ["archivedAt"] = 800000010.0, ["reason"] = "synced", ["deletionOrigin"] = "remote" });
        var result = NativeSyncProjection.Project(session, SyncProjectionPreferences(), [record]);
        var projectedTab = result.Single(p => p!["type"]!.GetValue<string>() == "tab")!["value"]!;
        Assert.Equal("3fffffffffffffff", projectedTab["orderToken"]!.GetValue<string>());
        Assert.Equal(tab["url"]!.GetValue<string>(), projectedTab["savedURL"]!.GetValue<string>());
        var archive = result.Single(p => p!["type"]!.GetValue<string>() == "archive")!["value"]!;
        Assert.Equal("deleted", archive["reason"]!.GetValue<string>());
        Assert.Equal("current", archive["tab"]!["placement"]!.GetValue<string>());
        Assert.Null(archive["tab"]!["folderID"]); Assert.Null(archive["tab"]!["splitGroupID"]); Assert.Null(archive["tab"]!["savedURL"]);
        Assert.Equal("remote", space["archivedTabs"]![0]!["deletionOrigin"]!.GetValue<string>());
    }

    [Fact]
    public void ReceivingArchivesDoesNotRewriteTheirCauseOrPositionsWhenRestaged() {
        var fixture = SavedSession(); var source = fixture.Document["session"]!.AsObject();
        var space = source["spaces"]![0]!; var template = space["tabs"]![0]!.DeepClone();
        source.Remove("disposableSeedMarker");
        space["tabs"] = new JsonArray(); space["folders"] = new JsonArray();
        space["history"] = new JsonArray(); space["selectedTabID"] = null;
        foreach (var (reason, index) in new[] { "autoCleanup", "quickWindow", "closed", "deleted" }.Select((r, i) => (r, i))) {
            var tab = template.DeepClone().AsObject(); tab["id"] = SwiftId(Guid.NewGuid());
            tab["placement"] = "current"; tab.Remove("savedURL"); tab.Remove("folderID"); tab.Remove("splitGroupID");
            space["archivedTabs"]!.AsArray().Add(new JsonObject {
                ["tab"] = tab,
                ["archivedAt"] = 800000001.0 + index,
                ["reason"] = reason
            });
        }
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        initial["records"] = new JsonArray(); initial["pendingRecordIDs"] = new JsonArray();
        NativeSyncJournal Staged(NativeSyncJournal journal, JsonNode session) =>
            journal.Stage(session.DeepClone().AsObject(), SyncDeletionReason.Superseded, 800000100.0);
        var sender = Staged(new NativeSyncJournal(Bytes(initial)), source);
        var sent = JsonNode.Parse(sender.Read())!;
        var seed = SavedSession().Document["session"]!.AsObject();
        var received = Transition(new NativeSyncJournal(Bytes(initial)), seed.DeepClone(), sent["records"]!.DeepClone(), replacing: true, now: 800000100.0);
        var materialized = received.Materialization["session"]!;
        Assert.All(materialized["spaces"]![0]!["archivedTabs"]!.AsArray(), a =>
            Assert.Equal("synced", a!["reason"]!.GetValue<string>()));
        var restaged = JsonNode.Parse(Staged(received.Journal, materialized).Read())!;
        Assert.Empty(restaged["pendingRecordIDs"]!.AsArray());
        Assert.Equal(sent["logicalClock"]!.GetValue<ulong>(), restaged["logicalClock"]!.GetValue<ulong>());
        Assert.True(JsonNode.DeepEquals(sent["records"], restaged["records"]));
        var added = materialized["spaces"]![0]!["archivedTabs"]![0]!.DeepClone().AsObject();
        var addedId = Guid.NewGuid(); added["tab"]!["id"] = SwiftId(addedId);
        added["reason"] = "quickWindow"; added.Remove("deletionOrigin"); added["archivedAt"] = 800000101.0;
        materialized["spaces"]![0]!["archivedTabs"]!.AsArray().Insert(0, added);
        var updated = JsonNode.Parse(Staged(received.Journal, materialized).Read())!;
        var pending = Assert.Single(updated["pendingRecordIDs"]!.AsArray())!;
        Assert.Equal(addedId, Guid.Parse(pending["value"]!.GetValue<string>()));
        var retained = updated["records"]!.AsArray().Where(r =>
            Guid.Parse(r!["id"]!["value"]!.GetValue<string>()) != addedId).Select(r => r!.DeepClone());
        Assert.True(JsonNode.DeepEquals(sent["records"], new JsonArray(retained.ToArray())));
    }

    [Fact]
    public void InvalidProjectionReportsTheOffendingIdentityWithoutMutatingTheSource() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var folder = session["spaces"]![0]!["folders"]![0]!;
        folder["parentID"] = folder["id"]!.DeepClone();
        var before = Bytes(session);
        var refused = Assert.Throws<SyncRecordsFlawedException>(() =>
            NativeSyncProjection.Project(session.AsObject(), SyncProjectionPreferences(), []));
        Assert.Equal(SyncRecordFlaw.InvalidFolderHierarchy, refused.Flaw);
        Assert.Equal(fixture.Space, refused.Subject);
        Assert.Equal(before, Bytes(session));
    }

    [Theory]
    [InlineData(true, 811679532.599763)]
    [InlineData(false, 811679532.600512)]
    public void ReceivingCommandEditsDoesNotCreateAnotherRevisionDuringRepair(bool renames, double now) {
        var fixture = SavedSession();
        var source = NativeSessionMaintenance.Repair(fixture.Document["session"]!.AsObject(), now)["session"]!;
        source.AsObject().Remove("disposableSeedMarker");
        source["spaces"]![0]!["history"] = new JsonArray();
        source["spaces"]![0]!["archivedTabs"] = new JsonArray();
        var initial = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()));
        initial["records"] = new JsonArray(); initial["pendingRecordIDs"] = new JsonArray();
        NativeSyncJournal Staged(NativeSyncJournal journal, JsonNode session) =>
            journal.Stage(session.DeepClone().AsObject(), SyncDeletionReason.Superseded, now);
        var sender = Staged(new NativeSyncJournal(Bytes(initial)), source);
        NativeSyncSessionTransition Receive(NativeSyncJournal journal, JsonNode local, string kind, NativeSyncJournal remote)
            => Transition(journal, local.DeepClone(), JsonNode.Parse(remote.Read())!["records"]!.DeepClone(), replacing: kind == "replace", now: now);
        var receiver = Receive(new NativeSyncJournal(Bytes(initial)), source, "replace", sender);
        var authority = TestWorkspaces.Session(source);
        authority.Handle(renames ? new RenameTab(Guid.Empty, fixture.Space, fixture.Tab, "Renamed on the other device")
            : new MoveTab(Guid.Empty, fixture.Space, fixture.Tab, TabPlacement.Current, null, null, LeavesSplit: true),
            StoredSessionCodec.Date(now), new TestIds());
        source = JsonNode.Parse(authority.Checkpoint().Read("core"))!;
        sender = Staged(sender, source);
        var sent = JsonNode.Parse(sender.Read())!;
        receiver = Receive(receiver.Journal, receiver.Materialization["session"]!, "merge", sender);
        // Repeated delivery and a journal reload must remain acknowledgements, not edits.
        for (int i = 0; i < 2; i++) {
            var received = JsonNode.Parse(Staged(receiver.Journal, receiver.Materialization["session"]!).Read())!;
            Assert.Empty(received["pendingRecordIDs"]!.AsArray());
            Assert.Equal(sent["logicalClock"]!.GetValue<ulong>(), received["logicalClock"]!.GetValue<ulong>());
            var sentRecords = sent["records"]!.AsArray(); var receivedRecords = received["records"]!.AsArray();
            Assert.Equal(sentRecords.Count, receivedRecords.Count);
            foreach (var record in sentRecords) {
                var match = Assert.Single(receivedRecords, r => JsonNode.DeepEquals(record!["id"], r!["id"]))!;
                Assert.True(JsonNode.DeepEquals(record!["version"], match["version"]));
            }
            var actual = receiver.Materialization["session"]!["spaces"]![0]!["tabs"]![0]!;
            var field = renames ? "customTitle" : "placement";
            Assert.True(JsonNode.DeepEquals(source["spaces"]![0]!["tabs"]![0]![field], actual[field]));
            receiver = Receive(new NativeSyncJournal(Bytes(received)), receiver.Materialization["session"]!, "merge", sender);
        }
    }
}
