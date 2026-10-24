using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The upgrade every installed reader performs: the session, per-Space history
/// and sync journal the installed release kept in its defaults are carried into
/// the core's file once, and a file that cannot be opened is restored from the
/// recovery checkpoint the last good launch kept.
public sealed partial class BrowserContractsTests {
    /// The values an installed release left in its defaults: its session core
    /// with the selection it stored, each Space's history and its journal, from
    /// a session the installed app wrote.
    private static (JsonObject Core, LegacySession Values, JsonObject Journal) InstalledDefaults() {
        var parts = StoredParts(Path.Combine(AppContext.BaseDirectory, "Storage", "Fixtures", "installed-session.sqlite"));
        var core = StoredCore(parts);
        var spaces = core["spaces"]!.AsArray();
        core["selectedSpaceID"] = spaces[1]!["id"]!.DeepClone();
        spaces[1]!["selectedTabID"] = spaces[1]!["tabs"]![2]!["id"]!.DeepClone();
        var history = spaces.Select(space => new LegacyHistory(SpaceId(space!), parts[$"history.{SpaceId(space!).ToString().ToUpperInvariant()}"]))
            .ToArray();
        var journal = JsonNode.Parse(parts["journal"])!.AsObject();
        return (core, new LegacySession(Bytes(core), WholeGraph: null, history, parts["journal"]), journal);
    }

    /// The seed a platform hands an adoption, as it builds one.
    private static SessionState SeedSession() => StoredSessionCodec.DecodeInstalledSession(SavedSession().Document["session"]!.AsObject());

    /// The session `app` keeps in its file, opened as a launch opens it.
    private static NativeSessionAuthority StoredSession(CrestApp app) => app.Workspace(TestWorkspaces.OpenStored(app).Workspace);

    /// The session `app` keeps in its file, opened as a launch opens it, in
    /// the stored format with each Space's history inside it.
    private static JsonObject StoredDocument(CrestApp app) => StoredSessionCodec.Encode(StoredSession(app).Current);

    private static void AssertSameSession(JsonObject expected, JsonNode actual) {
        var differences = StoredJson.Differences(expected, actual, StoredJson.Comparison.AsSwiftReads);
        Assert.True(differences.Count == 0, string.Join(Environment.NewLine, differences));
    }

    [Fact]
    public void AnInstalledSessionIsCarriedWithItsHistoryAndJournalExactlyOnce() {
        using var directory = new StorageDirectory();
        var (core, installed, journal) = InstalledDefaults();
        var expected = core.DeepClone().AsObject();
        expected.Remove("selectedSpaceID");
        foreach (var space in expected["spaces"]!.AsArray()) {
            space!.AsObject().Remove("selectedTabID");
            space["history"] = JsonNode.Parse(installed.History.Single(part => part.SpaceId == SpaceId(space)).Entries);
        }

        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            Assert.Null(app.StoredSync);
            var adopted = Assert.Single(app.Send(new AdoptLegacySession(installed, SeedSession())).OfType<SessionAdopted>());
            // The split layout kept images in the platform's own store.
            Assert.Empty(adopted.Favicons);

            var stored = StoredDocument(app);
            AssertSameSession(expected, stored);
            var spaces = stored["spaces"]!.AsArray();
            Assert.Equal([13, 12], spaces.Select(space => space!["history"]!.AsArray().Count));
            Assert.Contains(spaces, space => space!["accessPolicy"]!.GetValue<string>() == "deviceOwnerAuthentication");
            Assert.Contains(spaces.SelectMany(space => space!["tabs"]!.AsArray()), tab => tab!["faviconURL"] is not null);
            Assert.NotEmpty(spaces.SelectMany(space => space!["splitGroups"]!.AsArray()));
            Assert.NotEmpty(spaces.SelectMany(space => space!["archivedTabs"]!.AsArray()));
            // A window without a record of its own still adopts the tabs the release showed.
            var window = Assert.IsType<WindowChanged>(Assert.Single(Own(app.Send(new OpenWindow(Guid.NewGuid(),
                TestWorkspaces.OpenStored(app).Workspace, Saved: true, null, null, [], RestoresTabs: true))))).Window;
            Assert.Contains(new ShownTab(SpaceId(spaces[1]!), SpaceId(spaces[1]!["tabs"]![2]!)), window.ShownTabs);

            // The journal keeps its device identity, clock, records and the uploads still owed.
            var carried = JsonNode.Parse(app.StoredSync!.Snapshot.Read())!;
            foreach (var member in new[] { "deviceID", "logicalClock", "records", "pendingRecordIDs" })
                Assert.True(StoredJson.Differences(journal[member], carried[member], StoredJson.Comparison.AsSwiftReads).Count == 0, member);
            Assert.NotEmpty(journal["pendingRecordIDs"]!.AsArray());
            // A recovery copy exists before the app writes anything else.
            Assert.True(File.Exists(directory.Recovery));
            Assert.False(File.Exists(directory.File + ".cloud-recovery"));
        }

        // A later launch keeps the accepted session, even when the retained
        // defaults have since changed.
        var changed = new LegacySession(Bytes(SavedSession().Document["session"]!), WholeGraph: null, [], installed.Journal);
        using var relaunched = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        relaunched.Drain();
        Assert.Empty(Own(relaunched.Send(new AdoptLegacySession(changed, SeedSession()))));
        AssertSameSession(expected, StoredDocument(relaunched));
        Assert.Equal(journal["records"]!.AsArray().Count, JsonNode.Parse(relaunched.StoredSync!.Snapshot.Read())!["records"]!.AsArray().Count);
    }

    [Fact]
    public void AWholeGraphSessionHandsBackItsImagesAndItsTabGroupsBecomeOpenFolders() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        var space = document["spaces"]![0]!.AsObject();
        var open = Guid.NewGuid();
        var image = new byte[] { 1, 2, 3, 250 };
        space["tabs"]!.AsArray().Add(new JsonObject {
            ["id"] = SwiftId(open),
            ["title"] = "Grouped",
            ["url"] = "https://example.org/",
            ["symbol"] = "globe",
            ["placement"] = "current",
            ["lastActivatedAt"] = 800000000.0,
            ["faviconData"] = Convert.ToBase64String(image)
        });
        // More history than a Space keeps: the newest entries stay, as recording a visit keeps them.
        var history = space["history"]!.AsArray();
        for (int entry = 0; entry < HistoryEntryState.MaximumEntries + 10; entry++)
            history.Add(new JsonObject {
                ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(),
                ["url"] = $"https://example.com/older/{entry}",
                ["title"] = "Older visit",
                ["firstVisitedAt"] = 700000000.0,
                ["lastVisitedAt"] = 700000000.0 - entry,
                ["visitCount"] = 1
            });
        var group = Guid.NewGuid();
        document["currentTabFolders"] = new JsonArray(
            new JsonObject {
                ["id"] = new JsonObject { ["rawValue"] = 1 },
                ["folderID"] = SwiftId(group),
                ["spaceID"] = SwiftId(fixture.Space),
                ["tabs"] = new JsonArray(SwiftId(open), SwiftId(fixture.Tab)),
                ["title"] = "Research",
                ["color"] = "blue",
                ["isCollapsed"] = true
            },
            // A group none of whose tabs is still open adds no folder.
            new JsonObject {
                ["id"] = new JsonObject { ["rawValue"] = 2 },
                ["folderID"] = SwiftId(Guid.NewGuid()),
                ["spaceID"] = SwiftId(fixture.Space),
                ["tabs"] = new JsonArray(SwiftId(fixture.Tab)),
                ["color"] = "a color from later"
            });

        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var adopted = Assert.Single(app.Send(new AdoptLegacySession(
            new LegacySession(Core: null, Bytes(document), [], Journal: null), SeedSession())).OfType<SessionAdopted>());

        var favicon = Assert.Single(adopted.Favicons);
        Assert.Equal(open, favicon.TabId);
        Assert.Equal(image, favicon.Image);
        var carried = StoredDocument(app)["spaces"]![0]!;
        var folder = Assert.Single(carried["folders"]!.AsArray(), item => item!["location"]!.GetValue<string>() == "current")!;
        Assert.Equal(group, SpaceId(folder));
        Assert.Equal("Research", folder["title"]!.GetValue<string>());
        Assert.True(folder["isCollapsed"]!.GetValue<bool>());
        Assert.Equal(0.04, folder["color"]!["red"]!.GetValue<double>());
        var tabs = carried["tabs"]!.AsArray();
        Assert.Equal(group, Guid.Parse(tabs.Single(tab => SpaceId(tab!) == open)!["folderID"]!["rawValue"]!.GetValue<string>()));
        // Only an open tab outside every folder joins; the saved tab keeps its folder.
        Assert.NotEqual(group, Guid.Parse(tabs.Single(tab => SpaceId(tab!) == fixture.Tab)!["folderID"]!["rawValue"]!.GetValue<string>()));
        Assert.Equal(HistoryEntryState.MaximumEntries, carried["history"]!.AsArray().Count);
        Assert.Equal("Earlier visit", carried["history"]![0]!["title"]!.GetValue<string>());
        Assert.Null(StoredDocument(app)["currentTabFolders"]);
    }

    [Fact]
    public void AnInstalledSessionWithTermsThisBuildCannotNameIsCarriedNotReplaced() {
        using var directory = new StorageDirectory();
        var (core, installed, _) = InstalledDefaults();
        var space = core["spaces"]![1]!.AsObject();
        space["accent"] = "chartreuse";
        space["accessPolicy"] = "hardwareKeyRequired";
        var tab = space["tabs"]![0]!.AsObject();
        tab["placement"] = "hibernated";
        tab["storedIconMode"] = "generated";
        core["spaces"]![0]!.AsObject().Remove("accessPolicy");

        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        app.Send(new AdoptLegacySession(installed with { Core = Bytes(core) }, SeedSession()));

        var spaces = StoredDocument(app)["spaces"]!.AsArray();
        Assert.Equal(core["spaces"]!.AsArray().Select(item => SpaceId(item!)), spaces.Select(item => SpaceId(item!)));
        Assert.Equal("indigo", spaces[1]!["accent"]!.GetValue<string>());
        // An unreadable restriction keeps the Space guarded; none at all is open.
        Assert.Equal("deviceOwnerAuthentication", spaces[1]!["accessPolicy"]!.GetValue<string>());
        Assert.Equal("open", spaces[0]!["accessPolicy"]!.GetValue<string>());
        var carriedTab = spaces[1]!["tabs"]!.AsArray().Single(item => SpaceId(item!) == SpaceId(tab))!;
        Assert.Equal("saved", carriedTab["placement"]!.GetValue<string>());
        Assert.Null(carriedTab["storedIconMode"]);
        Assert.Equal(12, spaces[1]!["history"]!.AsArray().Count);
        Assert.False(File.Exists(directory.File + ".cloud-recovery"));
    }

    [Fact]
    public void AnUnreadableInstalledSessionLeavesTheSeedAndAsksTheCloudForAFullPull() {
        var seed = SavedSession().Document["session"]!.AsObject();
        var (_, installed, _) = InstalledDefaults();
        using (var directory = new StorageDirectory()) {
            // The whole graph is never read while a core is present.
            var unreadable = new LegacySession(Bytes(JsonValue.Create("a core a later build may read")!), installed.Core, installed.History,
                installed.Journal);
            using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
            Assert.Single(app.Send(new AdoptLegacySession(unreadable, StoredSessionCodec.DecodeInstalledSession(seed))).OfType<SessionAdopted>());
            Assert.Equal(Guid.Parse(seed["disposableSeedMarker"]!.GetValue<string>()),
                Guid.Parse(StoredDocument(app)["disposableSeedMarker"]!.GetValue<string>()));
            Assert.True(File.Exists(directory.File + ".cloud-recovery"));
            // The seed carries no journal, so there is no complete checkpoint to keep.
            Assert.False(File.Exists(directory.Recovery));
        }
        using (var directory = new StorageDirectory()) {
            using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
            app.Send(new AdoptLegacySession(new LegacySession(null, null, [], installed.Journal), StoredSessionCodec.DecodeInstalledSession(seed)));
            Assert.Equal(SpaceId(seed["spaces"]![0]!), SpaceId(StoredDocument(app)["spaces"]![0]!));
            Assert.False(File.Exists(directory.File + ".cloud-recovery"));
        }
    }

    /// A file with nothing to carry and no seed takes the session a first
    /// launch starts with: one Personal Space in the Winter house look,
    /// showing a Start Page, marked as the disposable seed. A launch without a
    /// file asks the same session of the standalone answers.
    [Fact]
    public void AFileWithNothingToCarryTakesTheFirstInstallSession() {
        using var directory = new StorageDirectory();
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        app.Send(new AdoptLegacySession(new LegacySession(Core: null, WholeGraph: null, [], Journal: null), Seed: null));

        foreach (var session in new[] { StoredSession(app).Current, new StandaloneAnswers().Query(new FirstInstallSession()) }) {
            var space = Assert.Single(session.Spaces);
            Assert.Equal(("Personal", "person.fill", SpaceAccent.Indigo), (space.Settings.Name, space.Settings.Symbol, space.Settings.Accent));
            Assert.True(Assert.Single(space.Tabs).IsStartPage);
            Assert.NotNull(session.DisposableSeedMarker);
        }
        Assert.False(File.Exists(directory.File + ".cloud-recovery"));
    }

    [Fact]
    public void AJournalFromANewerReleaseRefusesTheCarryAndWritesNothing() {
        using var directory = new StorageDirectory();
        var (_, installed, journal) = InstalledDefaults();
        journal["schemaVersion"] = 2;
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var refused = Assert.Throws<Rejected>(() => app.Send(new AdoptLegacySession(installed with { Journal = Bytes(journal) }, SeedSession())));
        Assert.IsType<StorageFromNewerApp>(refused.Rejection);
        Assert.Null(app.StoredSync);
        Assert.DoesNotContain("core", StoredParts(directory.File).Keys);
    }

    [Fact]
    public void ARestoreReplacesAFileTheCoreCannotOpenWithTheCheckpointAndPreservesIt() {
        using var directory = new StorageDirectory();
        var (_, installed, journal) = InstalledDefaults();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        JsonNode expected;
        using (var app = new CrestApp(configuration)) {
            app.Send(new AdoptLegacySession(installed, SeedSession()));
            expected = StoredDocument(app);
        }
        var broken = "not a session"u8.ToArray();
        var sidecar = "preserve this WAL"u8.ToArray();
        File.WriteAllBytes(directory.File, broken);
        File.WriteAllBytes(directory.File + "-wal", sidecar);
        Assert.IsType<StorageUnreadable>(Assert.Throws<Rejected>(() => new CrestApp(configuration)).Rejection);

        Assert.Equal((CoreStatus.Ok, (Rejection?)null), AppClient.Restore(configuration));

        using (var restored = new CrestApp(configuration)) {
            AssertSameSession(expected.AsObject(), StoredDocument(restored));
            var carried = JsonNode.Parse(restored.StoredSync!.Snapshot.Read())!;
            // A new device identity, so no version issued after the checkpoint is reissued.
            Assert.NotEqual(journal["deviceID"]!.GetValue<string>(), carried["deviceID"]!.GetValue<string>());
            foreach (var member in new[] { "logicalClock", "records", "pendingRecordIDs" })
                Assert.True(StoredJson.Differences(journal[member], carried[member], StoredJson.Comparison.AsSwiftReads).Count == 0, member);
        }
        var preserved = Assert.Single(Directory.GetDirectories(directory.Path, "Recovery-*"));
        Assert.Equal(broken, File.ReadAllBytes(Path.Combine(preserved, SessionStorage.FileName)));
        Assert.Equal(sidecar, File.ReadAllBytes(Path.Combine(preserved, SessionStorage.FileName + "-wal")));
        Assert.True(File.Exists(directory.File + ".cloud-recovery"));
        Assert.False(File.Exists(directory.File + ".restore-pending"));
    }

    [Fact]
    public void AnUnusableCheckpointLeavesTheFileAloneAndAnInterruptedRestoreCanResume() {
        using var directory = new StorageDirectory();
        var (_, installed, _) = InstalledDefaults();
        var configuration = new AppConfiguration(directory.Path, DevicePlatform.Desktop);
        Assert.Equal((CoreStatus.Rejected, (Rejection?)new RecoveryCheckpointUnusable(StorageFailure.Unavailable)), AppClient.Restore(configuration));
        using (var app = new CrestApp(configuration)) app.Send(new AdoptLegacySession(installed, SeedSession()));
        var checkpoint = File.ReadAllBytes(directory.Recovery);

        var original = "original bytes"u8.ToArray();
        File.WriteAllBytes(directory.File, original);
        File.WriteAllBytes(directory.Recovery, "invalid checkpoint"u8.ToArray());
        Assert.Equal((CoreStatus.Rejected, (Rejection?)new RecoveryCheckpointUnusable(StorageFailure.Damaged)), AppClient.Restore(configuration));
        Assert.Equal(original, File.ReadAllBytes(directory.File));
        Assert.False(File.Exists(directory.File + ".restore-pending"));

        // A restore that stopped after setting the file aside refuses the
        // directory, so a fresh seed can never stand in, and runs again.
        File.WriteAllBytes(directory.Recovery, checkpoint);
        File.Delete(directory.File);
        File.WriteAllBytes(directory.File + ".restore-pending", []);
        Assert.IsType<StorageRestoreInterrupted>(Assert.Throws<Rejected>(() => new CrestApp(configuration)).Rejection);
        Assert.Equal((CoreStatus.Ok, (Rejection?)null), AppClient.Restore(configuration));
        using var restored = new CrestApp(configuration);
        Assert.NotNull(restored.StoredSync);
    }
}
