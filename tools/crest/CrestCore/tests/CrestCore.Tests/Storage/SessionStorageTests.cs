using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The session file the core owns: the format earlier releases wrote, what
/// is on disk when a call returns, and what a crash can and cannot lose.
public sealed unsafe partial class BrowserContractsTests {
    private static int wakes;

    /// A new directory the test owns, removed with everything in it.
    private sealed class StorageDirectory : IDisposable {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "crest-storage-" + Guid.NewGuid().ToString("N"));
        public string File => System.IO.Path.Combine(Path, SessionStorage.FileName);
        public string Recovery => System.IO.Path.Combine(Path, "session.recovery.sqlite");

        public StorageDirectory() => Directory.CreateDirectory(Path);

        public void Dispose() => Directory.Delete(Path, recursive: true);
    }

    private static Dictionary<string, byte[]> StoredParts(string file) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadOnly);
        return connection.Parts().ToDictionary(part => part, part => connection.Read(part)!, StringComparer.Ordinal);
    }

    private static void AssertSameParts(Dictionary<string, byte[]> expected, Dictionary<string, byte[]> actual) {
        Assert.Equal(expected.Keys.Order(StringComparer.Ordinal), actual.Keys.Order(StringComparer.Ordinal));
        foreach (var (part, bytes) in expected) Assert.True(bytes.AsSpan().SequenceEqual(actual[part]), $"{part} changed");
    }

    /// Writes a session file the way an earlier release did: one table, one
    /// row per part, storage version 1.
    private static void WriteStoredFile(string file, JsonObject session, JsonObject? journal, int version = 1) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        connection.Execute("CREATE TABLE checkpoint (part TEXT PRIMARY KEY, data BLOB NOT NULL)");
        connection.Execute($"PRAGMA user_version={version}");
        var core = session.DeepClone().AsObject();
        foreach (var space in core["spaces"]!.AsArray()) {
            var id = Guid.Parse(space!["id"]!["rawValue"]!.GetValue<string>());
            connection.Write("history." + id.ToString("D").ToUpperInvariant(), Bytes(space["history"]!));
            space["history"] = new JsonArray();
        }
        connection.Write("core", Bytes(core));
        if (journal is not null) connection.Write("journal", Bytes(journal));
    }

    /// Makes the file refuse every write to `part`, as a full disk or a
    /// failing device refuses one mid-transaction.
    private static void RefuseWrites(string file, string part) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite);
        foreach (var operation in new[] { "INSERT", "UPDATE" })
            connection.Execute($"CREATE TRIGGER refuse_{operation} BEFORE {operation} ON checkpoint WHEN NEW.part = '{part}' "
                + "BEGIN SELECT RAISE(ABORT, 'refused'); END");
    }

    private static void AcceptWrites(string file) {
        using var connection = SqliteConnection.Open(file, Sqlite.OpenReadWrite);
        connection.Execute("DROP TRIGGER refuse_INSERT");
        connection.Execute("DROP TRIGGER refuse_UPDATE");
    }

    private static JsonObject StoredCore(Dictionary<string, byte[]> parts) => JsonNode.Parse(parts["core"])!.AsObject();

    /// Gives an empty file `document` as its first session, as a launch does
    /// when the installed release kept that session whole, with `journal`.
    private static AdoptLegacySession Adoption(JsonObject document, JsonObject? journal = null) =>
        new(new LegacySession(Core: null, WholeGraph: Bytes(document), History: [], journal is null ? null : Bytes(journal)),
            Seed: null);

    /// Drains `app` until `done` holds for what arrived, starting from the
    /// changes an intent already `answered`: a change the core started
    /// before that intent returned travels in its answer instead.
    private static IReadOnlyList<Change> DrainUntil(CrestApp app, Func<IReadOnlyList<Change>, bool> done,
        IReadOnlyList<Change>? answered = null) {
        var drained = new List<Change>(answered ?? []);
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!done(drained) && DateTime.UtcNow < deadline) {
            drained.AddRange(app.Drain());
            Thread.Sleep(5);
        }
        return drained;
    }

    /// Drains `app` until a launch over an adopted session has saved it and
    /// staged it. Attaching sync first announces the journal it found, which
    /// holds nothing to upload, and the launch stage announces what it staged
    /// after it, a drain later when the save already travelled in the answer.
    private static IReadOnlyList<Change> DrainLaunch(CrestApp app, IReadOnlyList<Change> answered) =>
        DrainUntil(app, changes => changes.OfType<Saved>().Any()
            && changes.Any(change => change is SyncJournalChanged { PendingRecords: > 0 }), answered);

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void CountWake(nint context) {
        Assert.Equal(42, context);
        Interlocked.Increment(ref wakes);
    }

    [Fact]
    public void ASessionTheInstalledAppWroteLoadsAndIsWrittenBackUnchanged() {
        using var directory = new StorageDirectory();
        File.Copy(Path.Combine(AppContext.BaseDirectory, "Storage", "Fixtures", "installed-session.sqlite"), directory.File);
        var original = StoredParts(directory.File);

        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var spaces = StoredDocument(app)["spaces"]!.AsArray();
            Assert.Equal(["Work", "Personal"], spaces.Select(space => space!["name"]!.GetValue<string>()));
            Assert.Equal("deviceOwnerAuthentication", spaces[1]!["accessPolicy"]!.GetValue<string>());
            Assert.Equal([13, 12], spaces.Select(space => space!["history"]!.AsArray().Count));
            Assert.Equal([12, 8], spaces.Select(space => space!["tabs"]!.AsArray().Count));
            var journal = JsonNode.Parse(app.StoredSync!.Snapshot.Read())!;
            Assert.Equal(30, journal["records"]!.AsArray().Count);
            Assert.Equal(27, journal["pendingRecordIDs"]!.AsArray().Count);
        }

        // The launch save found nothing to change, and recovery kept the file as it was.
        AssertSameParts(original, StoredParts(directory.File));
        AssertSameParts(original, StoredParts(directory.Recovery));
    }

    [Fact]
    public void AcceptedEditsAreSavedBehindInOrderAndOnlyNewerRevisionsAreAnnounced() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            Assert.Null(app.StoredSync);
            app.Send(Adoption(document));
            var workspace = TestWorkspaces.OpenStored(app).Workspace;
            for (int edit = 1; edit <= 20; edit++) app.Send(Renaming(workspace, document, $"Edit {edit}"));
            var announced = DrainUntil(app, changes => changes.OfType<Saved>().Any(saved => saved.Revision == 21));
            var saved = announced.OfType<Saved>().Select(change => change.Revision).ToArray();
            Assert.Equal(21, saved[^1]);
            Assert.Equal(saved.Order(), saved);
            Assert.Equal(saved.Distinct(), saved);
            Assert.DoesNotContain(announced, change => change is StorageFailed);
        }
        using var reopened = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var tabs = StoredDocument(reopened)["spaces"]![0]!["tabs"]!.AsArray();
        Assert.Equal("Edit 20", tabs[0]!["customTitle"]!.GetValue<string>());
    }

    [Fact]
    public void AnEditWritesOnlyThePartsItChanged() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        _ = DrainUntil(app, changes => changes.OfType<Saved>().Any(), app.Send(Adoption(document)));
        // Every write the core makes from here on leaves a `log.` row naming its part.
        using (var connection = SqliteConnection.Open(directory.File, Sqlite.OpenReadWrite)) {
            foreach (var operation in new[] { "INSERT", "UPDATE" })
                connection.Execute($"CREATE TRIGGER log_{operation} AFTER {operation} ON checkpoint WHEN NEW.part NOT LIKE 'log.%' "
                    + "BEGIN INSERT INTO checkpoint(part, data) VALUES ('log.' || NEW.part || '.' || hex(randomblob(8)), x'01'); END");
        }
        app.Send(Renaming(TestWorkspaces.OpenStored(app).Workspace, document, "Only the title"));
        _ = DrainUntil(app, changes => changes.OfType<Saved>().Any(saved => saved.Revision == 2));

        var written = StoredParts(directory.File).Keys.Where(part => part.StartsWith("log.", StringComparison.Ordinal))
            .Select(part => part["log.".Length..part.LastIndexOf('.')]).ToArray();
        Assert.Equal(["core"], written);
    }

    [Fact]
    public void ACommandStagedWithItsSaveIsOnDiskWithItsJournalBeforeItReturnsOrNeitherChanges() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        var second = document["spaces"]![0]!.DeepClone().AsObject();
        second["id"] = SwiftId(Guid.NewGuid()); second["profile"]!["id"] = Guid.NewGuid().ToString();
        second["tabs"] = new JsonArray(); second["folders"] = new JsonArray(); second["history"] = new JsonArray();
        document["spaces"]!.AsArray().Add(second);
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var answered = app.Send(Adoption(document));
        var (workspace, opened) = TestWorkspaces.OpenStored(app);
        var session = app.Workspace(workspace);
        var sync = app.StoredSync!;
        sync.Flush();
        var launched = DrainLaunch(app, [.. answered, .. opened]);
        Assert.Contains(launched, change => change is SyncJournalChanged { PendingRecords: > 0 });
        var deleting = SpaceId(second);
        var operation = Guid.NewGuid();
        app.Send(new BeginDeletingSpace(workspace, Guid.NewGuid(), deleting, operation));
        // The deletion is on disk before the platform erases the profile's data.
        Assert.NotNull(JsonNode.Parse(StoredParts(directory.File)["core"])!["spaceDeletions"]);
        app.Send(new DeleteProfileData(Guid.NewGuid(), Guid.Parse(second["profile"]!["id"]!.GetValue<string>()), Ephemeral: false));
        var staged = sync.Snapshot;
        var before = StoredParts(directory.File);

        // The platform erased the profile's data; the removal is on disk with
        // its journal when the intent returns, or neither changes.
        RefuseWrites(directory.File, "journal");
        Assert.IsType<SaveFailed>(Assert.Throws<Rejected>(() =>
            app.Send(new FinishDeletingSpace(workspace, Guid.NewGuid(), deleting, operation))).Rejection);
        Assert.Equal(2UL, session.Revision);
        Assert.Same(staged, sync.Snapshot);
        AssertSameParts(before, StoredParts(directory.File));

        AcceptWrites(directory.File);
        app.Send(new FinishDeletingSpace(workspace, Guid.NewGuid(), deleting, operation));
        Assert.Equal(3UL, session.Revision);
        var after = StoredParts(directory.File);
        Assert.True(after["core"].AsSpan().SequenceEqual(session.Checkpoint().Read("core")));
        Assert.True(after["journal"].AsSpan().SequenceEqual(sync.Snapshot.Read()));
        var tombstone = JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray().Single(record =>
            record!["id"]!["kind"]!.GetValue<string>() == "space" && JsonNode.DeepEquals(record["spaceID"], second["id"]));
        Assert.Equal("explicitDelete", tombstone!["tombstone"]!["reason"]!.GetValue<string>());
    }

    [Fact]
    public void APrivateWorkspaceStartsFromThePrivateTemplateAndReachesNeitherTheFileNorTheJournal() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        Dictionary<string, byte[]> before;
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var answered = app.Send(Adoption(document));
            var (_, opened) = TestWorkspaces.OpenStored(app);
            var sync = app.StoredSync!;
            sync.Flush();
            _ = DrainLaunch(app, [.. answered, .. opened]);
            before = StoredParts(directory.File);
            var staged = sync.Snapshot;

            // It opens with the one private Space a private window starts with.
            var workspace = Assert.Single(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)).OfType<WorkspaceOpened>());
            var space = Assert.Single(workspace.Session.Spaces);
            Assert.Equal(WorkspaceKind.Private, workspace.Kind);
            Assert.Equal(("Private", "eyeglasses", BuiltInSearchProvider.DuckDuckGo, CurrentTabCleanup.Never, false),
                (space.Settings.Name, space.Settings.Symbol, space.Settings.BrowsingPreferences.SelectedBuiltInEngine,
                    space.Settings.BrowsingPreferences.CurrentTabCleanup, space.Settings.CredentialPreferences.IsEnabled));
            Assert.Single(space.Tabs);

            // What it browses stays in memory: nothing is saved or staged.
            var window = Guid.NewGuid();
            app.Send(new OpenWindow(window, workspace.WorkspaceId, Saved: false, null, null, [], RestoresTabs: true));
            app.Send(new OpenTab(workspace.WorkspaceId, window, space.Id, Guid.NewGuid(),
                new TabContent("https://private.example/", null, "Private page"), TabPlacement.Current, null, false));
            app.Send(new SetSpaceIdentity(workspace.WorkspaceId, space.Id, "Renamed in private", "eyeglasses", SpaceAccent.Teal));
            Assert.Null(app.Workspace(workspace.WorkspaceId).Storage);
            Assert.Same(staged, sync.Snapshot);
            Assert.DoesNotContain(app.Drain(), change => change is Saved or SyncJournalChanged);
        }
        // Closing the core saves whatever is still pending, and none of it was private.
        AssertSameParts(before, StoredParts(directory.File));
    }

    [Fact]
    public void AJournalIsNeverWrittenAheadOfTheSessionItWasStagedFrom() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        var device = Guid.NewGuid();
        var journal = JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 9, device));
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        app.Send(Adoption(document, journal));
        app.Send(Renaming(TestWorkspaces.OpenStored(app).Workspace, document, "Edited before staging"));
        app.Send(new AcknowledgeUploads([new(new(SyncRecordKind.Tab, fixture.Tab), new SyncVersion(9, device))]));

        // Whichever write came first, the journal is on disk with the session it followed.
        var stored = StoredParts(directory.File);
        Assert.True(stored["journal"].AsSpan().SequenceEqual(app.StoredSync!.Snapshot.Read()));
        Assert.Equal("Edited before staging", StoredCore(stored)["spaces"]![0]!["tabs"]![0]!["customTitle"]!.GetValue<string>());
    }

    [Fact]
    public void RecoveryKeepsTheSessionExactlyAsLoadedAndRepairIsTheFirstSave() {
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var document = fixture.Document["session"]!.AsObject();
        // A second Space that reuses the first one's profile and tab: repair must
        // give it identities of its own.
        var twin = document["spaces"]![0]!.DeepClone().AsObject();
        twin["id"] = SwiftId(Guid.NewGuid());
        document["spaces"]!.AsArray().Add(twin);
        WriteStoredFile(directory.File, document, JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid())));
        var written = StoredParts(directory.File);

        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            AssertSameParts(written, StoredParts(directory.Recovery));
            var (workspace, opened) = TestWorkspaces.OpenStored(app);
            var spaces = app.Workspace(workspace).Current.Spaces;
            Assert.Equal(spaces, Assert.IsType<WorkspaceOpened>(opened.Single(change => change is WorkspaceOpened)).Session.Spaces);
            Assert.NotEqual(spaces[0].ProfileId, spaces[1].ProfileId);
            // The repaired tab wears the image the platform keeps for the tab it came from.
            var repaired = spaces[1].Tabs[0].Id;
            Assert.NotEqual(fixture.Tab, repaired);
            Assert.Equal(new TabCopied(workspace, fixture.Tab, repaired), Assert.Single(opened.OfType<TabCopied>()));
        }

        var saved = StoredCore(StoredParts(directory.File));
        var profiles = saved["spaces"]!.AsArray().Select(space => space!["profile"]!["id"]!.GetValue<string>()).ToArray();
        Assert.Equal(2, profiles.Distinct().Count());
        AssertSameParts(written, StoredParts(directory.Recovery));
    }

    [Fact]
    public void AFileTheCoreMustNotUseIsRefusedWithoutWritingToIt() {
        var document = SavedSession().Document["session"]!.AsObject();
        var journal = JournalDocument(SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid()));

        using (var newer = new StorageDirectory()) {
            WriteStoredFile(newer.File, document, journal, version: 2);
            var bytes = File.ReadAllBytes(newer.File);
            Assert.IsType<StorageFromNewerApp>(Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(newer.Path, DevicePlatform.Desktop))).Rejection);
            Assert.Equal(bytes, File.ReadAllBytes(newer.File));
        }
        using (var newerJournal = new StorageDirectory()) {
            var future = journal.DeepClone().AsObject();
            future["schemaVersion"] = 2;
            WriteStoredFile(newerJournal.File, document, future);
            Assert.IsType<StorageFromNewerApp>(
                Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(newerJournal.Path, DevicePlatform.Desktop))).Rejection);
        }
        using (var incomplete = new StorageDirectory()) {
            WriteStoredFile(incomplete.File, document, journal);
            using (var connection = SqliteConnection.Open(incomplete.File, Sqlite.OpenReadWrite))
                connection.Execute("DELETE FROM checkpoint WHERE part LIKE 'history.%'");
            var bytes = File.ReadAllBytes(incomplete.File);
            var refused = Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(incomplete.Path, DevicePlatform.Desktop))).Rejection;
            Assert.Equal(new StorageUnreadable(StorageFailure.Damaged), refused);
            Assert.Equal(bytes, File.ReadAllBytes(incomplete.File));
            Assert.False(File.Exists(incomplete.Recovery));
        }
        using (var restoring = new StorageDirectory()) {
            File.WriteAllBytes(restoring.File + ".restore-pending", []);
            Assert.IsType<StorageRestoreInterrupted>(
                Assert.Throws<Rejected>(() => new CrestApp(new AppConfiguration(restoring.Path, DevicePlatform.Desktop))).Rejection);
            Assert.False(File.Exists(restoring.File));
        }
    }

    [Fact]
    public void TheHostIsWokenOnceForChangesTheCoreStartedAndDrainsThemInOrder() {
        using var directory = new StorageDirectory();
        using var memoryOnly = new AppClient();
        Assert.Equal(CoreStatus.Ok, memoryOnly.SettleSync());
        Assert.Equal(new NoStoredSession(), memoryOnly.Refuse(new PendingUploads()));

        using var app = new AppClient(directory.Path);
        Assert.Equal(CoreStatus.Ok, app.SettleSync());
        Assert.Equal(new NoStoredSession(), app.Refuse(new PendingUploads()));
        Assert.Equal(new NoStoredSession(), app.Refuse(new OpenWorkspace(WorkspaceKind.Persistent, Seed: null)));
        Volatile.Write(ref wakes, 0);
        Assert.Equal(CoreStatus.Ok, app.SetWake(&CountWake, 42));
        var adoption = Adoption(SavedSession().Document["session"]!.AsObject());
        // The file now holds a session, which opens as a workspace of its own.
        // Its first save runs behind the intent: a save that lands before the
        // intent answers travels in that answer, and one that lands after
        // wakes the host once for a drain.
        var answer = app.Send(adoption);
        Assert.Equal([typeof(SessionAdopted)], answer.Where(change => change is not Saved).Select(change => change.GetType()));
        if (answer.OfType<Saved>().SingleOrDefault() is { } early) {
            Assert.Equal(new Saved(1), early);
        } else {
            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (Volatile.Read(ref wakes) == 0 && DateTime.UtcNow < deadline) Thread.Sleep(5);
            Assert.Equal(1, Volatile.Read(ref wakes));
            Assert.Equal([new Saved(1)], app.Drain());
        }
        Assert.Empty(app.Drain());
        // The file holds a session now, so a second adoption finds nothing to do.
        Assert.Empty(app.Send(adoption));
        Assert.Equal(CoreStatus.Ok, app.SetWake(null, 0));

        var opened = Assert.Single(app.Send(new OpenWorkspace(WorkspaceKind.Persistent, Seed: null)).OfType<WorkspaceOpened>());
        Assert.Equal(WorkspaceKind.Persistent, opened.Kind);
        Assert.Equal(CoreStatus.Ok, app.SettleSync());
    }
}
