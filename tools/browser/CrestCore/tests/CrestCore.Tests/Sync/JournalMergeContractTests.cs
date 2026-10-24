using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// How the journal resolves two versions of one record: whole records by
/// version, fields that carry their own clocks by the later clock, an explicit
/// deletion over any edit, and the more durable placement when neither moved
/// the tab. Two devices that merge each other's records hold the same ones.
public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    [Fact]
    public void AnExplicitDeletionWinsOverANewerEdit() {
        var space = FirstSpace(OneSpaceSession());
        var tab = space["tabs"]![0]!.AsObject();
        var journal = new JournalUnderTest(Fixed(6));

        journal.Merge(SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 20, Fixed(4)));
        journal.Merge(TombstoneRecord(SyncRecordKind.Tab, Fixed(102), Fixed(100), 10, Fixed(5), SyncDeletionReason.ExplicitDelete, 200));

        var resolved = journal.Record(SyncRecordKind.Tab, Fixed(102))!;
        Assert.Null(resolved["payload"]);
        Assert.Equal("explicitDelete", resolved["tombstone"]!["reason"]!.GetValue<string>());
    }

    /// When neither copy moved the tab, the more durable placement survives,
    /// and the merged record waits to upload since neither device wrote it.
    [Fact]
    public void AConcurrentPlacementMergeKeepsTheMoreDurablePlacement() {
        var tab = FirstSpace(OneSpaceSession())["tabs"]![0]!.AsObject();
        var current = SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 20, Fixed(8));
        var pinned = Edited(current, 10, Fixed(7), value => value["placement"] = "pinned");
        var journal = new JournalUnderTest(Fixed(9));

        journal.Merge(pinned);
        journal.Merge(current);

        Assert.Equal("pinned", journal.Value(SyncRecordKind.Tab, Fixed(102))!["placement"]!.GetValue<string>());
        Assert.Contains(Name(SyncRecordKind.Tab, Fixed(102)), journal.Pending);
    }

    [Fact]
    public void TheLaterSavedTabsDisclosureWinsOverAHigherStaleClock() {
        var stale = SavedRecord(SyncRecordKind.Space, SpaceValue(FirstSpace(OneSpaceSession())), 100, Fixed(940));
        stale["payload"]!["value"]!["isSavedTabsExpanded"] = true;
        stale["payload"]!["value"]!["savedTabsExpansionModifiedAt"] = At(200);
        var latest = Edited(stale, 10, Fixed(941), value => {
            value["isSavedTabsExpanded"] = false;
            value["savedTabsExpansionModifiedAt"] = At(300);
        });

        var resolved = ConvergedValue(SyncRecordKind.Space, Fixed(100), stale, latest);

        Assert.False(resolved["isSavedTabsExpanded"]!.GetValue<bool>());
        Assert.Equal(300, Unix(resolved["savedTabsExpansionModifiedAt"]), precision: 6);
    }

    [Fact]
    public void TheLaterFolderDisclosureWinsOverAHigherStaleClock() {
        var stale = SavedRecord(SyncRecordKind.Folder, new JsonObject {
            ["id"] = SwiftId(Fixed(944)),
            ["spaceID"] = SwiftId(Fixed(100)),
            ["title"] = "Projects",
            ["symbol"] = "folder",
            ["location"] = "saved",
            ["isCollapsed"] = false,
            ["collapseModifiedAt"] = At(200),
            ["orderToken"] = "a"
        }, 100, Fixed(945));
        var latest = Edited(stale, 10, Fixed(946), value => {
            value["isCollapsed"] = true;
            value["collapseModifiedAt"] = At(300);
        });

        var resolved = ConvergedValue(SyncRecordKind.Folder, Fixed(944), stale, latest);

        Assert.True(resolved["isCollapsed"]!.GetValue<bool>());
        Assert.Equal(300, Unix(resolved["collapseModifiedAt"]), precision: 6);
    }

    [Fact]
    public void TheLaterMoveWinsOverAHigherStaleClock() {
        var tab = FirstSpace(OneSpaceSession())["tabs"]![0]!.AsObject();
        var stale = Edited(SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 0, Fixed(93)), 100, Fixed(93), value => {
            value["placement"] = "pinned";
            value["orderToken"] = "b";
            value["positionModifiedAt"] = At(200);
        });
        var latest = Edited(stale, 10, Fixed(94), value => {
            value["placement"] = "current";
            value["orderToken"] = "a";
            value["positionModifiedAt"] = At(300);
        });

        var resolved = ConvergedValue(SyncRecordKind.Tab, Fixed(102), stale, latest);

        Assert.Equal("current", resolved["placement"]!.GetValue<string>());
        Assert.Equal("a", resolved["orderToken"]!.GetValue<string>());
        Assert.Equal(300, Unix(resolved["positionModifiedAt"]), precision: 6);
    }

    [Fact]
    public void TheLaterRenameWinsOverAHigherStaleClock() {
        var tab = FirstSpace(OneSpaceSession())["tabs"]![0]!.AsObject();
        var stale = Edited(SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 0, Fixed(97)), 100, Fixed(97), value => {
            value["customTitle"] = "Stale Name";
            value["titleModifiedAt"] = At(200);
        });
        var latest = Edited(stale, 10, Fixed(98), value => {
            value["customTitle"] = "Latest Name";
            value["titleModifiedAt"] = At(300);
        });

        var resolved = ConvergedValue(SyncRecordKind.Tab, Fixed(102), stale, latest);

        Assert.Equal("Latest Name", resolved["customTitle"]!.GetValue<string>());
        Assert.Equal(300, Unix(resolved["titleModifiedAt"]), precision: 6);
    }

    [Fact]
    public void ALaterClearedRenameBeatsAnEarlierRenameOnAnotherDevice() {
        var tab = FirstSpace(OneSpaceSession())["tabs"]![0]!.AsObject();
        var renamed = Edited(SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 0, Fixed(107)), 100, Fixed(107), value => {
            value["customTitle"] = "Stale Name";
            value["titleModifiedAt"] = At(200);
        });
        var cleared = Edited(renamed, 10, Fixed(108), value => {
            value.Remove("customTitle");
            value["titleModifiedAt"] = At(400);
        });

        var resolved = ConvergedValue(SyncRecordKind.Tab, Fixed(102), renamed, cleared);

        Assert.Null(resolved["customTitle"]);
        Assert.Equal(400, Unix(resolved["titleModifiedAt"]), precision: 6);
    }

    /// A Space record from a build before split metadata carries none, which is
    /// no opinion: the metadata the other copy holds survives however the
    /// records are ordered.
    [Fact]
    public void AnOlderClientsSpaceRecordCannotStripSplitMetadata() {
        var group = Fixed(1_192);
        var session = SplitSession([group, group]);
        FirstSpace(session)["splitGroups"] = new JsonArray(new JsonObject {
            ["id"] = SwiftId(group),
            ["customTitle"] = "Preserved",
            ["titleModifiedAt"] = At(300)
        });
        var journal = new JournalUnderTest(Fixed(1_193));
        journal.Stage(session, at: 400);
        var aware = Edited(journal.Record(SyncRecordKind.Space, Fixed(1_100))!, 10, Fixed(1_194), _ => { });
        var legacy = Edited(aware, 100, Fixed(1_195), value => value.Remove("splitGroups"));

        var resolved = ConvergedValue(SyncRecordKind.Space, Fixed(1_100), aware, legacy);

        var kept = Assert.Single(resolved["splitGroups"]!.AsArray())!;
        Assert.Equal("Preserved", kept["customTitle"]!.GetValue<string>());
    }

    /// Two devices renaming and tinting one split merge per field, each by its
    /// own clock.
    [Fact]
    public void ConcurrentSplitRenameAndTintMergePerField() {
        var group = Fixed(1_198);
        JsonObject Metadata(string title, double titled, double red, double tinted) => new() {
            ["id"] = SwiftId(group),
            ["customTitle"] = title,
            ["titleModifiedAt"] = At(titled),
            ["tint"] = new JsonObject { ["red"] = red, ["green"] = 0.5, ["blue"] = 0.2, ["alpha"] = 1.0 },
            ["tintModifiedAt"] = At(tinted)
        };
        var session = SplitSession([group, group]);
        FirstSpace(session)["splitGroups"] = new JsonArray(Metadata("Original", 100, 0.1, 100));
        var journal = new JournalUnderTest(Fixed(1_199));
        journal.Stage(session, at: 200);
        var baseline = journal.Record(SyncRecordKind.Space, Fixed(1_100))!;
        var renamed = Edited(baseline, 20, Fixed(1_200),
            value => value["splitGroups"] = new JsonArray(Metadata("Renamed Elsewhere", 500, 0.1, 100)));
        var tinted = Edited(baseline, 30, Fixed(1_201), value => value["splitGroups"] = new JsonArray(Metadata("Original", 100, 0.7, 600)));

        var result = NativeSyncEvaluator.Resolve(renamed, tinted)["payload"]!["value"]!["splitGroups"]![0]!;

        Assert.Equal("Renamed Elsewhere", result["customTitle"]!.GetValue<string>());
        Assert.Equal(500, Unix(result["titleModifiedAt"]), precision: 6);
        Assert.Equal(0.7, result["tint"]!["red"]!.GetValue<double>());
        Assert.Equal(600, Unix(result["tintModifiedAt"]), precision: 6);
    }

    /// A build before split view re-saves a tab it only activated: a higher
    /// clock and a later activation, but no split membership and no move.
    /// Membership rides the move's clock, so the aware copy keeps it.
    [Fact]
    public void AnOlderClientsActivationCannotStripSplitMembership() {
        var group = Fixed(1_130);
        var journal = new JournalUnderTest(Fixed(1_131));
        journal.Stage(SplitSession([group, group], positioned: 300), at: 300);
        var grouped = Edited(journal.Record(SyncRecordKind.Tab, Fixed(1_101))!, 10, Fixed(1_132), _ => { });
        var stripped = Edited(grouped, 100, Fixed(1_133), value => {
            value["positionModifiedAt"] = At(100);
            value["lastActivatedAt"] = At(400);
            value.Remove("splitGroupID");
        });

        var resolved = ConvergedValue(SyncRecordKind.Tab, Fixed(1_101), grouped, stripped);

        Assert.Equal(group, StoredSessionCodec.Identity(resolved["splitGroupID"]));
        Assert.Equal(300, Unix(resolved["positionModifiedAt"]), precision: 6);
        Assert.Equal(400, Unix(resolved["lastActivatedAt"]), precision: 6);
    }

    /// The older build may move the tab, and moving a member out of its run
    /// ends its membership however old the build is.
    [Fact]
    public void AnOlderClientsMoveEndsSplitMembership() {
        var group = Fixed(1_140);
        var journal = new JournalUnderTest(Fixed(1_141));
        journal.Stage(SplitSession([group, group], positioned: 300), at: 300);
        var grouped = Edited(journal.Record(SyncRecordKind.Tab, Fixed(1_101))!, 100, Fixed(1_142), _ => { });
        var moved = Edited(grouped, 10, Fixed(1_143), value => {
            value["orderToken"] = "ffffffffffffffff";
            value["positionModifiedAt"] = At(500);
            value.Remove("splitGroupID");
        });

        var resolved = ConvergedValue(SyncRecordKind.Tab, Fixed(1_101), grouped, moved);

        Assert.Null(resolved["splitGroupID"]);
        Assert.Equal("ffffffffffffffff", resolved["orderToken"]!.GetValue<string>());
        Assert.Equal(500, Unix(resolved["positionModifiedAt"]), precision: 6);
    }

    /// Records from before moves carried a clock have no move clock at all, so
    /// neither copy can claim it cleared membership: the copy that knows the
    /// group keeps it.
    [Fact]
    public void SplitMembershipSurvivesRecordsWithoutAnyMoveClock() {
        var group = Fixed(1_180);
        var journal = new JournalUnderTest(Fixed(1_181));
        journal.Stage(SplitSession([group, group]), at: 300);
        var grouped = Edited(journal.Record(SyncRecordKind.Tab, Fixed(1_101))!, 10, Fixed(1_182), _ => { });
        Assert.Null(grouped["payload"]!["value"]!["positionModifiedAt"]);
        var stripped = Edited(grouped, 100, Fixed(1_183), value => {
            value["lastActivatedAt"] = At(400);
            value.Remove("splitGroupID");
        });

        var resolved = ConvergedValue(SyncRecordKind.Tab, Fixed(1_101), grouped, stripped);

        Assert.Equal(group, StoredSessionCodec.Identity(resolved["splitGroupID"]));
        Assert.Null(resolved["positionModifiedAt"]);
    }

    [Fact]
    public void AVisitMergeKeepsTheWholeObservedRange() {
        JsonObject Visit(string title, double first, double last, int count) => new() {
            ["id"] = Fixed(10).ToString("D").ToUpperInvariant(),
            ["spaceID"] = SwiftId(Fixed(100)),
            ["url"] = "https://example.com",
            ["title"] = title,
            ["firstVisitedAt"] = At(first),
            ["lastVisitedAt"] = At(last),
            ["visitCount"] = count
        };
        var journal = new JournalUnderTest(Fixed(11));
        journal.Merge(SavedRecord(SyncRecordKind.History, Visit("Earlier", 10, 20, 2), 5, Fixed(12)));

        journal.Merge(SavedRecord(SyncRecordKind.History, Visit("Later", 15, 40, 5), 6, Fixed(13)));

        var visit = journal.Value(SyncRecordKind.History, Fixed(10))!;
        Assert.Equal("Later", visit["title"]!.GetValue<string>());
        Assert.Equal(10, Unix(visit["firstVisitedAt"]), precision: 6);
        Assert.Equal(40, Unix(visit["lastVisitedAt"]), precision: 6);
        Assert.Equal(5, visit["visitCount"]!.GetValue<int>());
    }

    /// A retention tombstone written with a higher clock loses to a tab
    /// activated after it.
    [Fact]
    public void ANewerActivationDefeatsARetentionTombstoneWithAHigherClock() {
        var tab = FirstSpace(OneSpaceSession(activated: 300))["tabs"]![0]!.AsObject();
        var journal = new JournalUnderTest(Fixed(142));

        journal.Merge(TombstoneRecord(SyncRecordKind.Tab, Fixed(102), Fixed(100), 100, Fixed(141), SyncDeletionReason.Retention, 200));
        journal.Merge(SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 10, Fixed(140)));

        Assert.Equal(300, Unix(journal.Value(SyncRecordKind.Tab, Fixed(102))!["lastActivatedAt"]), precision: 6);
    }

    [Fact]
    public void TwoDevicesConvergeAfterConcurrentRenames() {
        var baseline = OneSpaceSession();
        var first = new JournalUnderTest(Fixed(30));
        var second = new JournalUnderTest(Fixed(31));
        first.Stage(baseline);
        second.Merge(first.Records);
        first.MarkUploaded();
        var firstEdit = baseline.DeepClone().AsObject();
        FirstSpace(firstEdit)["name"] = "Athena";
        first.Stage(firstEdit, at: 200);
        var secondEdit = baseline.DeepClone().AsObject();
        FirstSpace(secondEdit)["name"] = "Orion";
        second.Stage(secondEdit, at: 200);

        var (firstRecords, secondRecords) = (first.Records, second.Records);
        first.Merge(secondRecords);
        second.Merge(firstRecords);

        Assert.Equal(FirstSpace(first.Materialize(baseline))["name"]!.GetValue<string>(),
            FirstSpace(second.Materialize(baseline))["name"]!.GetValue<string>());
        AssertSameRecords(first, second);
    }

    /// One device restyles a Space's crest while another adds a tab to it: the
    /// two edits touch different records and both survive.
    [Fact]
    public void ACrestEditAndATabAddedElsewhereBothSurvive() {
        var baseline = OneSpaceSession();
        var mac = new JournalUnderTest(Fixed(212));
        var phone = new JournalUnderTest(Fixed(213));
        mac.Stage(baseline);
        phone.Merge(mac.Records);
        mac.MarkUploaded();
        var macEdit = baseline.DeepClone().AsObject();
        FirstSpace(macEdit)["branding"] = JsonNode.Parse(SavedBranding);
        FirstSpace(macEdit)["branding"]!["crest"]!["symbol"] = "hammer";
        mac.Stage(macEdit, at: 200);
        var phoneEdit = baseline.DeepClone().AsObject();
        var added = Fixed(214);
        FirstSpace(phoneEdit)["tabs"]!.AsArray().Add(TabOf(added, "Cloud page", "http://localhost:3000"));
        phone.Stage(phoneEdit, at: 200);

        var (macRecords, phoneRecords) = (mac.Records, phone.Records);
        mac.Merge(phoneRecords);
        phone.Merge(macRecords);

        AssertSameRecords(mac, phone);
        var reconciled = FirstSpace(mac.Materialize(baseline));
        Assert.Equal("hammer", reconciled["branding"]!["crest"]!["symbol"]!.GetValue<string>());
        Assert.Contains(added, Ids(reconciled["tabs"]));
    }

    /// A record the codec builds in code holds its numbers as the CLR types the
    /// codec chose, while the same record parsed from text holds them as
    /// parsed text. Every typed journal update takes either and makes the
    /// same journal of them.
    [Fact]
    public void RecordsTheCodecBuildsReadLikeParsedRecordsInEveryJournalUpdate() {
        var session = OneSpaceSession(Fixed(1_100), Fixed(1_101), Fixed(1_102));
        var space = FirstSpace(session);
        space["history"] = new JsonArray(VisitOf(Fixed(1_103), "visited", count: 4));
        space["archivedTabs"] = new JsonArray(ArchivedOf(TabOf(Fixed(1_104), "Archived", "https://example.com/archived"), at: 950));
        var local = new JournalUnderTest(Fixed(1_105));
        local.Stage(session, at: 900);
        // Newer copies of every record the journal staged, as the cloud sends them.
        SyncRecord[] cloud = [.. local.Records.Select(Cloud).Select(record =>
            record with { Version = new SyncVersion(record.Version.Clock + 1_000, Fixed(1_106)) })];
        JsonArray Built() => new IncomingSyncRecords(cloud).Batch();
        JsonArray Parsed() => JsonNode.Parse(Built().ToJsonString())!.AsArray();
        UploadedRecord[] uploaded = [.. cloud.Select(record => new UploadedRecord(new(record.Kind, record.Id), record.Version))];
        var canonical = Canonical(session);

        foreach (var update in new Func<JsonArray, NativeSyncJournal>[] {
            records => local.Journal.Merge(records),
            records => local.Journal.Replace(records),
            records => local.Journal.Overwrite(canonical.DeepClone().AsObject(), records, At(1_000)),
            records => local.Journal.Merge(records).Acknowledge(uploaded),
            records => local.Journal.Replace(records).Stage(canonical.DeepClone().AsObject(), SyncDeletionReason.Superseded, At(1_000))
        }) {
            Assert.Equal(update(Parsed()).Read(), update(Built()).Read());
        }
    }

    #endregion

    #region Actions - Fixtures

    /// Merges `first` then `second` into one journal and `second` then `first`
    /// into another, asserts both hold the same records, and answers the value
    /// they resolved for the record of `kind` with identity `id`.
    private static JsonObject ConvergedValue(SyncRecordKind kind, Guid id, JsonObject first, JsonObject second) {
        var forward = new JournalUnderTest(Fixed(9_001));
        var backward = new JournalUnderTest(Fixed(9_002));
        forward.Merge(first);
        forward.Merge(second);
        backward.Merge(second);
        backward.Merge(first);
        AssertSameRecords(forward, backward);
        return forward.Value(kind, id)!;
    }

    #endregion
}
