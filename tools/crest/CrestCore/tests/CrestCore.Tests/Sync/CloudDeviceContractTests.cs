using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What a device that keeps its session in its file makes of the records the
/// cloud sends: records that arrive before their Space or folder wait instead
/// of being deleted, only web pages sync while what only this device shows
/// stays, and the person's choice between this device and the cloud replaces
/// or rebases as they chose.
public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    /// Only web pages enter sync. Native views, extension pages, files, data and
    /// script addresses and blank pages stay on this device, and a merge leaves
    /// them where they were.
    [Fact]
    public void OnlyWebPagesSyncAndWhatOnlyThisDeviceShowsSurvivesAMerge() {
        var local = OneSpaceSession();
        var space = FirstSpace(local);
        string[] addresses = [
            "https://example.org", "http://localhost:3000", "https://localhost:8443", "http://127.0.0.1:8080", "http://[::1]:8080",
            "chrome-extension://extension-test/index.html#/onboarding", "webkit-extension://extension-test/page.html",
            "file:///private/local.html", "data:text/html,hello", "javascript:alert(1)", "about:blank"
        ];
        for (int index = 0; index < addresses.Length; index++) {
            space["tabs"]!.AsArray().Add(TabOf(Fixed(1_400 + index), "Page", addresses[index], placement: index % 2 == 0 ? "saved" : "current"));
            space["archivedTabs"]!.AsArray().Add(ArchivedOf(TabOf(Fixed(1_500 + index), "Archived", addresses[index]), 100));
            space["history"]!.AsArray().Add(new JsonObject {
                ["id"] = Fixed(1_600 + index).ToString("D").ToUpperInvariant(),
                ["url"] = addresses[index],
                ["title"] = "Visited",
                ["firstVisitedAt"] = At(100),
                ["lastVisitedAt"] = At(100),
                ["visitCount"] = 1
            });
        }
        var tabs = space["tabs"]!.AsArray();
        tabs.Insert(1, NativeTabOf(Fixed(1_700), "settings", "Settings"));
        tabs.Insert(2, NativeTabOf(Fixed(1_701), "getting-started", "Getting Started"));
        tabs.Insert(3, new JsonObject {
            ["id"] = SwiftId(Fixed(1_702)),
            ["title"] = "Start Page",
            ["symbol"] = "flag.fill",
            ["placement"] = "current",
            ["lastActivatedAt"] = At(100)
        });
        local = NativeSessionMaintenance.Repair(Canonical(local), At(100), ids: new TestIds())["session"]!.AsObject();
        using var device = new SyncingDevice(local, Fixed(1_710));
        var journal = device.Journal;
        Assert.Equal(6, journal.Values(SyncRecordKind.Tab).Count);
        Assert.Equal(5, journal.Values(SyncRecordKind.Archive).Count);
        Assert.Equal(5, journal.Values(SyncRecordKind.History).Count);
        Assert.All(new[] { Fixed(1_700), Fixed(1_701), Fixed(1_702) }, native =>
            Assert.DoesNotContain(journal.Records, record => Guid.Parse(record["id"]!["value"]!.GetValue<string>()) == native));
        var remote = Edited(journal.Record(SyncRecordKind.Tab, Fixed(102))!, 10_000, Fixed(1_720),
            value => value["title"] = "Updated elsewhere");

        var merged = FirstSpace(device.Merge(remote));

        var before = StoredSessionCodec.DecodeSpace(FirstSpace(local));
        var after = StoredSessionCodec.DecodeSpace(merged);
        Assert.Equal("Updated elsewhere", after.Tabs.Single(tab => tab.Id == Fixed(102)).Title);
        Assert.Equal(before.Tabs.Where(tab => !IsWebPage(tab)), after.Tabs.Where(tab => !IsWebPage(tab)));
        Assert.Equal(before.ArchivedTabs.Select(archived => archived.Tab.Id).Order(), after.ArchivedTabs.Select(archived => archived.Tab.Id).Order());
        Assert.Equal(before.History.Select(visit => visit.Id).Order(), after.History.Select(visit => visit.Id).Order());
        Assert.Equal(1, after.Tabs.ToList().FindIndex(tab => tab.Id == Fixed(1_700)));
    }

    /// A batch has no ordering, so one member of a split can land alone. Repair
    /// keeps its membership, since stripping it would upload the strip to every
    /// other device, and the run comes back whole once its siblings arrive.
    [Fact]
    public void ALoneSplitMemberKeepsItsMembershipUntilItsSiblingsArrive() {
        var group = Fixed(1_160);
        var cloudSession = SplitSession([group, group, group], space: Fixed(1_161));
        var metadata = new JsonObject { ["id"] = SwiftId(group), ["customTitle"] = "Arriving Pair", ["titleModifiedAt"] = At(800) };
        FirstSpace(cloudSession)["splitGroups"] = new JsonArray(metadata.DeepClone());
        var members = Ids(FirstSpace(cloudSession)["tabs"]);
        var cloud = new JournalUnderTest(Fixed(1_162));
        cloud.Stage(cloudSession, at: 900);
        var later = members.Skip(1).Select(id => Name(SyncRecordKind.Tab, id)).ToHashSet();
        using var device = new SyncingDevice(OneSpaceSession(), Fixed(1_163));

        var lonely = SpaceIn(device.Merge(cloud.Records.Where(record => !later.Contains(RecordName(record["id"]!)))), Fixed(1_161))!;

        Assert.Equal([group], lonely["tabs"]!.AsArray().Select(tab => SplitOf(tab!)));
        Assert.Equal(StoredSessionCodec.DecodeSplitGroup(metadata), StoredSessionCodec.DecodeSplitGroup(Assert.Single(lonely["splitGroups"]!.AsArray())));
        var staged = device.Journal.Value(SyncRecordKind.Tab, members[0])!;
        Assert.Equal(group, SplitOf(staged));
        Assert.Equal(cloud.Value(SyncRecordKind.Tab, members[0])!["orderToken"]!.GetValue<string>(), staged["orderToken"]!.GetValue<string>());

        var whole = SpaceIn(device.Merge(cloud.Records.Where(record => later.Contains(RecordName(record["id"]!)))), Fixed(1_161))!;

        Assert.Equal(members, Ids(whole["tabs"]));
        Assert.Equal([group, group, group], whole["tabs"]!.AsArray().Select(tab => SplitOf(tab!)));
        Assert.Equal(StoredSessionCodec.DecodeSplitGroup(metadata), StoredSessionCodec.DecodeSplitGroup(Assert.Single(whole["splitGroups"]!.AsArray())));
    }

    /// A tab deleted on purpose on another device leaves this one into the
    /// archive as deleted there, dated when it was deleted, and its archive
    /// record reads as a deletion everywhere.
    [Fact]
    public void AnExplicitDeletionFromTheCloudArchivesTheTabAsDeletedElsewhere() {
        var session = OneSpaceSession();
        FirstSpace(session)["tabs"]![0]!["placement"] = "pinned";
        using var device = new SyncingDevice(session, Fixed(1_185));
        device.MarkUploaded();

        var space = FirstSpace(device.Merge(
            TombstoneRecord(SyncRecordKind.Tab, Fixed(102), Fixed(100), 100, Fixed(1_186), SyncDeletionReason.ExplicitDelete, 500)));

        Assert.DoesNotContain(Fixed(102), Ids(space["tabs"]));
        var archive = StoredSessionCodec.DecodeArchivedTab(space["archivedTabs"]!.AsArray()
            .Single(item => StoredSessionCodec.Identity(item!["tab"]!["id"]) == Fixed(102)));
        Assert.Equal(ArchiveReason.DeletedOnAnotherDevice, archive.Reason);
        Assert.Equal(StoredSessionCodec.Date(At(500)), archive.ArchivedAt);
        Assert.Equal("deleted", device.Journal.Value(SyncRecordKind.Archive, Fixed(102))!["reason"]!.GetValue<string>());
    }

    /// Choosing this device's copy writes every record above the cloud's, the
    /// Space as this device holds it and a tombstone for what only the cloud
    /// holds, and leaves every record waiting to upload.
    [Fact]
    public void ChoosingThisDeviceRebasesItAboveTheCloudAndDeletesWhatOnlyTheCloudHolds() {
        var local = OneSpaceSession();
        var cloudSession = local.DeepClone().AsObject();
        FirstSpace(cloudSession)["name"] = "Cloud copy";
        FirstSpace(cloudSession)["tabs"]!.AsArray().Add(TabOf(Fixed(910), "Cloud only", "https://cloud.example.com", "icloud", activated: 900));
        var cloud = new JournalUnderTest(Fixed(911));
        cloud.Stage(cloudSession, at: 900);
        ulong cloudClock = cloud.Records.Max(record => record["version"]!["logicalClock"]!.GetValue<ulong>());
        using var device = new SyncingDevice(local, new JournalUnderTest(Fixed(912)));

        device.Overwrite(cloud.Records);

        var journal = device.Journal;
        var space = journal.Record(SyncRecordKind.Space, Fixed(100))!;
        Assert.Equal("Test", space["payload"]!["value"]!["name"]!.GetValue<string>());
        Assert.True(space["version"]!["logicalClock"]!.GetValue<ulong>() > cloudClock);
        var cloudOnly = journal.Record(SyncRecordKind.Tab, Fixed(910))!;
        Assert.Null(cloudOnly["payload"]);
        Assert.NotNull(cloudOnly["tombstone"]);
        Assert.True(cloudOnly["version"]!["logicalClock"]!.GetValue<ulong>() > cloudClock);
        Assert.Equal(journal.Records.Select(record => RecordName(record["id"]!)).ToHashSet(), journal.Pending);
    }

    [Fact]
    public void ChoosingTheCloudReplacesThisDevicesCopyWithoutUploadingItBack() {
        var cloudSession = OneSpaceSession();
        FirstSpace(cloudSession)["name"] = "Chosen from iCloud";
        var cloud = new JournalUnderTest(Fixed(920));
        cloud.Stage(cloudSession, at: 900);
        cloud.MarkUploaded();
        using var device = new SyncingDevice(OneSpaceSession(), Fixed(921));

        var resolved = device.Replace(cloud.Records);

        Assert.Equal("Chosen from iCloud", FirstSpace(resolved)["name"]!.GetValue<string>());
        Assert.Empty(device.Journal.Pending);
        AssertSameRecords(cloud, device.Journal);
    }

    /// A first sync splits across batches with no ordering between them, so a
    /// Space's tabs and visits can arrive before the Space. The earlier batch
    /// must not read the missing Space as a deletion: its tombstones would
    /// outrank the real records and delete the content on every device.
    [Fact]
    public void RecordsThatArriveBeforeTheirSpaceWaitForIt() {
        var cloudSession = OneSpaceSession(Fixed(940), Fixed(941), Fixed(942));
        FirstSpace(cloudSession)["history"] = new JsonArray(VisitOf(Fixed(9_944), "cloud"));
        var cloud = new JournalUnderTest(Fixed(943));
        cloud.Stage(cloudSession, at: 900);
        string spaceName = Name(SyncRecordKind.Space, Fixed(940));
        var children = cloud.Records.Where(record => RecordName(record["id"]!) != spaceName).ToArray();
        Assert.NotEmpty(children);
        using var device = new SyncingDevice(OneSpaceSession(), Fixed(944));

        Assert.Null(SpaceIn(device.Merge(children), Fixed(940)));

        var held = device.Journal;
        foreach (var child in children)
            Assert.True(SameRecord(child, held.Records.Single(record => RecordName(record["id"]!) == RecordName(child["id"]!))),
                $"{RecordName(child["id"]!)} did not wait for its Space");
        var restored = SpaceIn(device.Merge(cloud.Records.Where(record => RecordName(record["id"]!) == spaceName)), Fixed(940))!;
        Assert.Equal([Fixed(942)], Ids(restored["tabs"]));
        Assert.Equal([Fixed(9_944)], restored["history"]!.AsArray().Select(visit => Guid.Parse(visit!["id"]!.GetValue<string>())));
        Assert.All(device.Journal.Records, record => Assert.NotNull(record["payload"]));
    }

    /// The cloud delivers a batch again: every record resolves against the
    /// copy the journal already holds at the same version, and nothing waits
    /// to upload or takes a new version.
    [Fact]
    public void ABatchDeliveredAgainResolvesAgainstItselfAndStagesNothing() {
        var cloudSession = OneSpaceSession(Fixed(960), Fixed(961), Fixed(962));
        FirstSpace(cloudSession)["history"] = new JsonArray(VisitOf(Fixed(9_963), "again", count: 3));
        var cloud = new JournalUnderTest(Fixed(963));
        cloud.Stage(cloudSession, at: 900);
        using var device = new SyncingDevice(OneSpaceSession(), Fixed(964));
        device.Merge(cloud.Records);
        device.MarkUploaded();
        var clock = device.Journal.Document["logicalClock"]!.GetValue<ulong>();

        var again = device.Merge(cloud.Records);

        Assert.Equal(3, SpaceIn(again, Fixed(960))!["history"]![0]!["visitCount"]!.GetValue<int>());
        Assert.Empty(device.Journal.Pending);
        Assert.Equal(clock, device.Journal.Document["logicalClock"]!.GetValue<ulong>());
    }

    /// One level down: a saved tab whose folder has not arrived waits for it
    /// instead of failing the batch it came in.
    [Fact]
    public void ASavedTabThatArrivesBeforeItsFolderWaitsForIt() {
        var (space, folder, current, saved) = (Fixed(980), Fixed(981), Fixed(982), Fixed(983));
        var cloud = new JournalUnderTest(Fixed(985));
        cloud.Stage(SessionOf(SpaceOf(space, Fixed(984), "Cloud", "cloud", folders: [FolderOf(folder, "Reading")], tabs: [
            TabOf(current, "Current", "https://example.com/current", activated: 500),
            TabOf(saved, "Saved", "https://example.com/saved", "bookmark", "saved", folder: folder, activated: 501)
        ])), at: 900);
        string folderName = Name(SyncRecordKind.Folder, folder);
        using var device = new SyncingDevice(OneSpaceSession(), Fixed(986));

        var heldBack = SpaceIn(device.Merge(cloud.Records.Where(record => RecordName(record["id"]!) != folderName)), space)!;

        Assert.Equal([current], Ids(heldBack["tabs"]));
        Assert.Empty(heldBack["folders"]!.AsArray());
        Assert.True(SameRecord(cloud.Record(SyncRecordKind.Tab, saved), device.Journal.Record(SyncRecordKind.Tab, saved)));

        var restored = SpaceIn(device.Merge(cloud.Records.Where(record => RecordName(record["id"]!) == folderName)), space)!;

        Assert.Equal([folder], Ids(restored["folders"]));
        var savedTab = restored["tabs"]!.AsArray().Single(tab => StoredSessionCodec.Identity(tab!["id"]) == saved)!;
        Assert.Equal("saved", savedTab["placement"]!.GetValue<string>());
        Assert.Equal(folder, StoredSessionCodec.Identity(savedTab["folderID"]));
        Assert.All(device.Journal.Records, record => Assert.NotNull(record["payload"]));
    }

    /// A folder deleted on another device keeps its tombstone, while the saved
    /// tab it held stays, promoted out of it at once.
    [Fact]
    public void AFolderDeletedElsewherePromotesTheTabItHeld() {
        var (space, folder, current, saved) = (Fixed(990), Fixed(991), Fixed(992), Fixed(993));
        var session = SessionOf(SpaceOf(space, Fixed(994), "Shared", "cloud", folders: [FolderOf(folder, "Reading")], tabs: [
            TabOf(current, "Current", "https://example.com/current", activated: 500),
            TabOf(saved, "Saved", "https://example.com/saved", "bookmark", "saved", folder: folder, activated: 501)
        ]));
        using var device = new SyncingDevice(session, Fixed(995));
        device.MarkUploaded();

        var resolved = SpaceIn(device.Merge(
            TombstoneRecord(SyncRecordKind.Folder, folder, space, 900, Fixed(996), SyncDeletionReason.ExplicitDelete, 900)), space)!;

        Assert.Empty(resolved["folders"]!.AsArray());
        Assert.Equal([current, saved], Ids(resolved["tabs"]).Order());
        Assert.Null(resolved["tabs"]!.AsArray().Single(tab => StoredSessionCodec.Identity(tab!["id"]) == saved)!["folderID"]);
        var record = device.Journal.Record(SyncRecordKind.Tab, saved)!;
        Assert.NotNull(record["payload"]);
        Assert.Null(record["tombstone"]);

        var moved = Edited(record, 901, Fixed(996), value => {
            value.Remove("folderID");
            value["positionModifiedAt"] = At(901);
        });
        var afterMove = SpaceIn(device.Merge(moved), space)!["tabs"]!.AsArray().Single(tab => StoredSessionCodec.Identity(tab!["id"]) == saved)!;

        Assert.Equal("saved", afterMove["placement"]!.GetValue<string>());
        Assert.Null(afterMove["folderID"]);
    }

    #endregion

    #region Actions - Fixtures

    /// Whether `tab` shows a web page, which sync carries.
    private static bool IsWebPage(TabState tab) =>
        tab.Url is { } url && (url.StartsWith("http:", StringComparison.Ordinal) || url.StartsWith("https:", StringComparison.Ordinal));

    #endregion
}
