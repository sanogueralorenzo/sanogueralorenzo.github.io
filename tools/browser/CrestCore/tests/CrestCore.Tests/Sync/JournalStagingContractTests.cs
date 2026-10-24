using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What staging a session writes to its journal: only what sync carries, new
/// versions only for real edits, stable fractional positions, and tombstones
/// only where the session holds evidence of a deletion.
public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    [Fact]
    public void AJournalCarriesAnAllowlistOfTheSessionNotTheSessionItself() {
        var session = SavedSession().Document["session"]!.AsObject();
        var journal = new JournalUnderTest(Fixed(1));

        journal.Stage(session);

        string text = journal.Journal.Read() is { } bytes ? System.Text.Encoding.UTF8.GetString(bytes) : "";
        foreach (string excluded in new[] { "selectedSpaceID", "selectedTabID", "credentialPreferences", "faviconURL", "iconAccent" })
            Assert.DoesNotContain(excluded, text, StringComparison.Ordinal);
        foreach (string excluded in new[] { "password", "cookie", "serviceWorker", "backForward" })
            Assert.DoesNotContain(excluded, text, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(session["spaces"]!.AsArray().Count, journal.Values(SyncRecordKind.Space).Count);
    }

    [Fact]
    public void RestagingAnUnchangedSessionIssuesNoVersionAndQueuesNothing() {
        var session = CurrentTabSession(3);
        var journal = new JournalUnderTest(Fixed(2));
        journal.Stage(session);
        journal.MarkUploaded();
        ulong clock = journal.Clock;

        journal.Stage(session, at: 200);

        Assert.Equal(clock, journal.Clock);
        Assert.Empty(journal.Pending);
    }

    [Fact]
    public void MovingATabStagesOnlyThatTab() {
        var session = CurrentTabSession(4);
        var journal = new JournalUnderTest(Fixed(220));
        journal.Stage(session);
        journal.MarkUploaded();
        var before = TabOrderTokens(journal);
        var tabs = FirstSpace(session)["tabs"]!.AsArray();
        var moved = tabs[3]!.DeepClone();
        tabs.RemoveAt(3);
        tabs.Insert(1, moved);
        var movedId = StoredSessionCodec.Identity(moved["id"]);

        journal.Stage(session, at: 200);

        Assert.Equal([Name(SyncRecordKind.Tab, movedId)], journal.Pending);
        var after = TabOrderTokens(journal);
        Assert.NotEqual(before[movedId], after[movedId]);
        foreach (var id in Ids(tabs).Where(id => id != movedId)) Assert.Equal(before[id], after[id]);
        Assert.Equal(Ids(tabs), Ids(FirstSpace(journal.Materialize(session))["tabs"]));
    }

    [Fact]
    public void InsertingATabKeepsEveryOtherPosition() {
        var session = CurrentTabSession(3);
        var journal = new JournalUnderTest(Fixed(221));
        journal.Stage(session);
        journal.MarkUploaded();
        var before = TabOrderTokens(journal);
        var inserted = Fixed(722);
        FirstSpace(session)["tabs"]!.AsArray().Insert(1, TabOf(inserted, "Inserted", "https://example.com/inserted", activated: 200));

        journal.Stage(session, at: 200);

        Assert.Equal([Name(SyncRecordKind.Tab, inserted)], journal.Pending);
        var after = TabOrderTokens(journal);
        foreach (var (id, token) in before) Assert.Equal(token, after[id]);
        var order = Ids(FirstSpace(session)["tabs"]);
        Assert.True(string.CompareOrdinal(after[order[0]], after[inserted]) < 0);
        Assert.True(string.CompareOrdinal(after[inserted], after[order[2]]) < 0);
    }

    [Fact]
    public void PositionsCompactOnceTheirGapsRunOutWithoutGrowing() {
        var session = CurrentTabSession(2);
        var journal = new JournalUnderTest(Fixed(222));
        journal.Stage(session);
        journal.MarkUploaded();
        bool compacted = false;

        for (int index = 0; index < 80; index++) {
            FirstSpace(session)["tabs"]!.AsArray().Insert(0,
                TabOf(Fixed(800 + index), $"Front {index}", $"https://example.com/front/{index}", activated: 300 + index));
            journal.Stage(session, at: 300 + index);
            compacted |= journal.Pending.Count > 1;
            journal.MarkUploaded();
        }

        Assert.True(compacted);
        var tokens = TabOrderTokens(journal);
        Assert.Equal(FirstSpace(session)["tabs"]!.AsArray().Count, tokens.Count);
        Assert.All(tokens.Values, token => Assert.Matches("^[0-9a-f]{16}$", token));
        Assert.Equal(Ids(FirstSpace(session)["tabs"]), Ids(FirstSpace(journal.Materialize(session))["tabs"]));
    }

    [Fact]
    public void ConcurrentMovesConvergeWithoutRewritingSiblings() {
        var baseline = CurrentTabSession(5);
        var first = new JournalUnderTest(Fixed(223));
        var second = new JournalUnderTest(Fixed(224));
        first.Stage(baseline);
        second.Merge(first.Records);
        first.MarkUploaded();
        var firstEdit = baseline.DeepClone().AsObject();
        var firstTabs = FirstSpace(firstEdit)["tabs"]!.AsArray();
        var last = firstTabs[4]!.DeepClone();
        firstTabs.RemoveAt(4);
        firstTabs.Insert(1, last);
        first.Stage(firstEdit, at: 200);
        var secondEdit = baseline.DeepClone().AsObject();
        var secondTabs = FirstSpace(secondEdit)["tabs"]!.AsArray();
        var head = secondTabs[0]!.DeepClone();
        secondTabs.RemoveAt(0);
        secondTabs.Insert(3, head);
        second.Stage(secondEdit, at: 200);

        var (firstRecords, secondRecords) = (first.Records, second.Records);
        first.Merge(secondRecords);
        second.Merge(firstRecords);

        AssertSameRecords(first, second);
        Assert.Equal(Ids(FirstSpace(first.Materialize(baseline))["tabs"]), Ids(FirstSpace(second.Materialize(baseline))["tabs"]));
    }

    /// Records an older build wrote with tokens that are not this build's
    /// fixed-width form take canonical positions on the next stage, without a
    /// migration of the journal.
    [Fact]
    public void LegacyPositionsTakeCanonicalTokensOnTheNextStage() {
        var session = OneSpaceSession();
        var space = FirstSpace(session);
        var tab = space["tabs"]![0]!.AsObject();
        var journal = new JournalUnderTest(Fixed(228));
        journal.Merge(SavedRecord(SyncRecordKind.Space, SpaceValue(space), 1, Fixed(229)),
            SavedRecord(SyncRecordKind.Tab, TabValue(tab, SpaceId(space)), 2, Fixed(229)));

        journal.Stage(session, at: 200);

        Assert.Equal(1, journal.Document["schemaVersion"]!.GetValue<int>());
        Assert.Equal([Name(SyncRecordKind.Space, SpaceId(space)), Name(SyncRecordKind.Tab, StoredSessionCodec.Identity(tab["id"]))],
            journal.Pending.Order(StringComparer.Ordinal));
        Assert.All(journal.Values(SyncRecordKind.Space).Concat(journal.Values(SyncRecordKind.Tab)),
            value => Assert.Matches("^[0-9a-f]{16}$", value["orderToken"]!.GetValue<string>()));
        var repaired = NativeSessionMaintenance.Repair(Canonical(session), At(1_000_000), ids: new TestIds())["session"]!;
        Assert.Equal(StoredSessionCodec.DecodeSession(repaired), StoredSessionCodec.DecodeSession(journal.Materialize(session)));
    }

    [Fact]
    public void TwoTabsWithOneIdentityRefuseToStage() {
        var session = CurrentTabSession(2);
        var tabs = FirstSpace(session)["tabs"]!.AsArray();
        var duplicate = StoredSessionCodec.Identity(tabs[0]!["id"]);
        tabs[1] = TabOf(duplicate, "Duplicate", "https://example.com/duplicate", activated: 200);
        var journal = new JournalUnderTest(Fixed(227));
        var before = journal.Journal.Read();

        var refused = Assert.Throws<SyncRecordsFlawedException>(() => journal.Stage(session, at: 200));

        Assert.Equal(SyncRecordFlaw.DuplicateRecord, refused.Flaw);
        Assert.Equal(before, journal.Journal.Read());
    }

    [Fact]
    public void ATabDeletedOnPurposeBecomesATombstoneThatWaitsToUpload() {
        var session = OneSpaceSession();
        var journal = new JournalUnderTest(Fixed(3));
        journal.Stage(session);
        journal.MarkUploaded();
        var tab = FirstSpace(session)["tabs"]![0]!.AsObject();
        FirstSpace(session)["tabs"] = new JsonArray();
        FirstSpace(session)["archivedTabs"] = new JsonArray(ArchivedOf(tab, 200, "closed", origin: "local"));

        journal.Stage(session, at: 200);

        var record = journal.Record(SyncRecordKind.Tab, Fixed(102))!;
        Assert.Null(record["payload"]);
        Assert.Equal("explicitDelete", record["tombstone"]!["reason"]!.GetValue<string>());
        Assert.Equal(200, Unix(record["tombstone"]!["deletedAt"]), precision: 6);
        Assert.Contains(Name(SyncRecordKind.Tab, Fixed(102)), journal.Pending);
    }

    [Fact]
    public void ATabMissingWithoutEvidenceOfADeletionKeepsItsRecord() {
        var session = OneSpaceSession();
        var journal = new JournalUnderTest(Fixed(301));
        journal.Stage(session);
        journal.MarkUploaded();
        FirstSpace(session)["tabs"] = new JsonArray();

        journal.Stage(session, SyncDeletionReason.Superseded, at: 200);

        Assert.NotNull(journal.Value(SyncRecordKind.Tab, Fixed(102)));
        Assert.Empty(journal.Pending);
    }

    [Theory]
    [InlineData("pinned")]
    [InlineData("saved")]
    public void AnOrdinaryArchiveNeverDeletesAPinnedOrSavedTab(string placement) {
        var session = OneSpaceSession();
        var tab = FirstSpace(session)["tabs"]![0]!.AsObject();
        tab["placement"] = placement;
        var journal = new JournalUnderTest(Fixed(303));
        journal.Stage(session);
        journal.MarkUploaded();
        FirstSpace(session)["tabs"] = new JsonArray();
        FirstSpace(session)["archivedTabs"] = new JsonArray(ArchivedOf(tab, 200, "synced"));

        journal.Stage(session, SyncDeletionReason.Superseded, at: 200);

        var record = journal.Record(SyncRecordKind.Tab, Fixed(102))!;
        Assert.Null(record["tombstone"]);
        Assert.Equal(placement, record["payload"]!["value"]!["placement"]!.GetValue<string>());
    }

    [Fact]
    public void AFolderIsDeletedOnlyForAnExplicitDeletion() {
        var session = OneSpaceSession();
        var folder = Fixed(310);
        FirstSpace(session)["folders"] = new JsonArray(FolderOf(folder, "Retained"));
        var journal = new JournalUnderTest(Fixed(302));
        journal.Stage(session);
        journal.MarkUploaded();
        FirstSpace(session)["folders"] = new JsonArray();

        journal.Stage(session, SyncDeletionReason.Superseded, at: 200);

        Assert.NotNull(journal.Value(SyncRecordKind.Folder, folder));
        Assert.Empty(journal.Pending);

        journal.Stage(session, SyncDeletionReason.ExplicitDelete, at: 300);

        Assert.Equal("explicitDelete", journal.Record(SyncRecordKind.Folder, folder)!["tombstone"]!["reason"]!.GetValue<string>());
    }

    [Fact]
    public void DeletingASpaceDeletesTheRecordsItOwned() {
        var deleted = FirstSpace(OneSpaceSession(Fixed(950), Fixed(952), Fixed(951)));
        var retained = FirstSpace(OneSpaceSession(Fixed(953), Fixed(954), Fixed(955)));
        var session = SessionOf(deleted.DeepClone().AsObject(), retained.DeepClone().AsObject());
        var journal = new JournalUnderTest(Fixed(956));
        journal.Stage(session);
        journal.MarkUploaded();

        journal.Stage(SessionOf(retained.DeepClone().AsObject()), at: 200);

        Assert.Null(journal.Record(SyncRecordKind.Space, Fixed(950))!["payload"]);
        Assert.Equal("explicitDelete", journal.Record(SyncRecordKind.Tab, Fixed(951))!["tombstone"]!["reason"]!.GetValue<string>());
    }

    /// A journal recovered from corruption holds no Space records, so the first
    /// stage after it recreates them. A record waiting for its Space is judged
    /// against the journal before that stage, which never saw the Space, and
    /// survives.
    [Fact]
    public void AnOrphanSurvivesTheStageThatFirstRecreatesItsSpace() {
        var session = OneSpaceSession();
        var orphanValue = TabValue(TabOf(Fixed(960), "From iCloud", "https://example.com/orphan", activated: 300), Fixed(100), "b");
        var orphan = SavedRecord(SyncRecordKind.Tab, orphanValue, 9, Fixed(961));
        var journal = new JournalUnderTest(Fixed(962));
        journal.Merge(orphan);

        journal.Stage(session, at: 400);

        Assert.True(NativeSyncEvaluator.Equivalent(orphan, journal.Record(SyncRecordKind.Tab, Fixed(960))));
    }

    [Fact]
    public void OverwritingTheCloudLeavesCategoriesThisDeviceDoesNotSyncAlone() {
        var cloudSession = OneSpaceSession();
        FirstSpace(cloudSession)["history"] = new JsonArray(VisitOf(Fixed(9_944), "cloud"));
        var cloud = new JournalUnderTest(Fixed(970));
        cloud.Stage(cloudSession, at: 900);
        var history = cloud.Records.Where(record => record["id"]!["kind"]!.GetValue<string>() == "history").ToArray();
        Assert.NotEmpty(history);
        var journal = new JournalUnderTest(Fixed(971), historyAndArchive: false);

        journal.Overwrite(OneSpaceSession(), cloud.Records, at: 1_000);

        foreach (var record in history) {
            string name = RecordName(record["id"]!);
            Assert.True(NativeSyncEvaluator.Equivalent(record, journal.Record(SyncRecordKind.History,
                Guid.Parse(record["id"]!["value"]!.GetValue<string>()))), $"{name} was overwritten while history sync is off");
            Assert.DoesNotContain(name, journal.Pending);
        }
    }

    [Fact]
    public void AnAcknowledgementOfAnOlderVersionLeavesTheNewerEditWaiting() {
        var session = OneSpaceSession();
        var journal = new JournalUnderTest(Fixed(201));
        journal.Stage(session);
        string space = Name(SyncRecordKind.Space, Fixed(100));
        var uploaded = journal.Version(space);
        FirstSpace(session)["name"] = "Newer local rename";
        journal.Stage(session, at: 200);

        journal.MarkUploaded(space, uploaded);

        Assert.Contains(space, journal.Pending);
        journal.MarkUploaded(space, journal.Version(space));
        Assert.DoesNotContain(space, journal.Pending);
    }

    [Fact]
    public void AStaleFetchedCopyLeavesAnUnacknowledgedLocalVersionWaiting() {
        var journal = new JournalUnderTest(Fixed(206));
        journal.Stage(OneSpaceSession());
        var local = journal.Records[0];
        var stale = local.DeepClone().AsObject();
        stale["version"] = new JsonObject { ["logicalClock"] = 0UL, ["deviceID"] = Fixed(207).ToString("D").ToUpperInvariant() };

        journal.Merge(stale);

        Assert.True(NativeSyncEvaluator.Equivalent(local, journal.Records[0]));
        Assert.Contains(RecordName(local["id"]!), journal.Pending);
    }

    /// An archive the cloud brought is marked as synced here, and staging it
    /// again sends back the reason it arrived with, never the local mark.
    [Fact]
    public void AReceivedArchiveIsMarkedSyncedHereWithoutEchoingTheMark() {
        var remote = OneSpaceSession();
        var tab = FirstSpace(remote)["tabs"]![0]!.AsObject();
        FirstSpace(remote)["tabs"] = new JsonArray();
        FirstSpace(remote)["archivedTabs"] = new JsonArray(ArchivedOf(tab, 500));
        var journal = new JournalUnderTest(Fixed(1_180));
        journal.Stage(remote, at: 600);
        journal.MarkUploaded();

        var materialized = journal.Materialize(OneSpaceSession());

        Assert.Equal("synced", FirstSpace(materialized)["archivedTabs"]![0]!["reason"]!.GetValue<string>());
        journal.Stage(materialized, at: 700);
        Assert.All(journal.Values(SyncRecordKind.Archive), archive => Assert.NotEqual("synced", archive["reason"]!.GetValue<string>()));
    }

    [Fact]
    public void MaterializingKeepsAnArchiveCauseThisDeviceAlreadyHolds() {
        var local = OneSpaceSession();
        var tab = FirstSpace(local)["tabs"]![0]!.AsObject();
        FirstSpace(local)["tabs"] = new JsonArray();
        FirstSpace(local)["archivedTabs"] = new JsonArray(ArchivedOf(tab, 500, "autoCleanup"));
        var journal = new JournalUnderTest(Fixed(1_181));
        journal.Stage(local, at: 600);

        var materialized = journal.Materialize(local);

        Assert.Equal("autoCleanup", FirstSpace(materialized)["archivedTabs"]![0]!["reason"]!.GetValue<string>());
    }

    #endregion

    #region Actions - Fixtures

    /// Each tab record's position, by the tab's identity.
    private static Dictionary<Guid, string> TabOrderTokens(JournalUnderTest journal) => journal.Values(SyncRecordKind.Tab)
        .ToDictionary(value => StoredSessionCodec.Identity(value["id"]), value => value["orderToken"]!.GetValue<string>());

    /// Both journals hold the same records, each equivalent as every client reads it.
    private static void AssertSameRecords(JournalUnderTest first, JournalUnderTest second) {
        var (a, b) = (first.Records, second.Records);
        Assert.Equal(a.Count, b.Count);
        for (int index = 0; index < a.Count; index++) Assert.True(SameRecord(a[index], b[index]), $"{RecordName(a[index]["id"]!)} differs");
    }

    /// Whether two records in the journal's form are the same record at the
    /// same version, carrying what every client reads the same way: a record
    /// the cloud brought holds the defaults its reader filled in.
    private static bool SameRecord(JsonObject? first, JsonObject? second) {
        if (first is null || second is null) return first is null && second is null;
        JsonNode Body(JsonObject record) => SyncRecordBody.Read(record["tombstone"] ?? record["payload"], record["tombstone"] is not null,
            SyncPayloadForm.Journal).Write(SyncPayloadForm.Cloud);
        return NativeSyncEvaluator.Equivalent(first["id"], second["id"]) && NativeSyncEvaluator.Equivalent(first["spaceID"], second["spaceID"])
            && NativeSyncEvaluator.Equivalent(first["version"], second["version"]) && NativeSyncEvaluator.Equivalent(Body(first), Body(second));
    }

    #endregion
}
