using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Imports into the persistent workspace: what each kind creates, which Space
/// the importing window shows, the identities sync reads as global, where each
/// imported tab came from, what is on disk when an import returns, and the
/// rules that refuse one.
public sealed partial class BrowserContractsTests {
    /// Spaces in the stored format, as a review or manual setup carries them.
    private static byte[] ImportedSpaces(params JsonNode[] spaces) =>
        Encoding.UTF8.GetBytes(new JsonArray([.. spaces.Select(space => space.DeepClone())]).ToJsonString());

    /// Spaces as `ImportSpaces` carries them, read from the stored format.
    private static IReadOnlyList<SpaceState> ReadSpaces(params JsonNode[] spaces) =>
        NativeWorkspaceImport.Decoded(ImportedSpaces(spaces));

    /// A stored-format Space with its own identities, named `name`, holding `tabs`.
    private static JsonObject ImportedSpace(string name, params JsonObject[] tabs) => new() {
        ["id"] = SwiftId(Guid.NewGuid()),
        ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString().ToUpperInvariant() },
        ["name"] = name,
        ["symbol"] = "globe",
        ["accent"] = "indigo",
        ["tabs"] = new JsonArray([.. tabs]),
        ["folders"] = new JsonArray(),
        ["history"] = new JsonArray(),
        ["archivedTabs"] = new JsonArray()
    };

    /// A stored-format open tab at `url` in `placement`, in `folder` when named.
    private static JsonObject ImportedTab(string url, string placement = "current", Guid? folder = null) {
        var tab = new JsonObject {
            ["id"] = SwiftId(Guid.NewGuid()),
            ["title"] = url,
            ["url"] = url,
            ["placement"] = placement,
            ["lastActivatedAt"] = 800000000.0
        };
        if (placement != "current") tab["savedURL"] = url;
        if (folder is { } id) tab["folderID"] = SwiftId(id);
        return tab;
    }

    private static SpaceCustomization Customization(string name) =>
        new(name);

    private static Guid TabId(JsonNode tab) => Guid.Parse(tab["id"]!["rawValue"]!.GetValue<string>());

    /// The flow the last `ImportFlowChanged` among `changes` published.
    private static ImportFlowState Flowing(IReadOnlyList<Change> changes) =>
        Assert.IsType<ImportFlowChanged>(changes.Last(change => change is ImportFlowChanged)).Flow!;

    /// Opens setup over `device`'s workspace and reviews `spaces`, as Arc
    /// brought them.
    private static ImportReview Reviewing(TestDevice device, params JsonNode[] spaces) {
        device.Send(new StartBrowserImport(device.Workspace));
        device.Send(new OfferImportSources([ImportSource.Arc]));
        device.Send(new ToggleImportSource(ImportSource.Arc));
        device.Send(new ContinueImport());
        return Flowing(device.Send(new ReviewImport(ImportSource.Arc, ReadSpaces(spaces), []))).Review!;
    }

    [Fact]
    public void AReviewedImportKeepsItsTabGroupsAndTheSplitsThatStillHoldTogether() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        Guid group = Guid.NewGuid(), kept = Guid.NewGuid(), broken = Guid.NewGuid();
        JsonObject InSplit(JsonObject tab, Guid split) {
            tab["splitGroupID"] = SwiftId(split);
            return tab;
        }
        var moved = InSplit(ImportedTab("https://broken-two.example/"), broken);
        var space = ImportedSpace("Grouped", ImportedTab("https://group-one.example/", folder: group),
            ImportedTab("https://group-two.example/", folder: group), InSplit(ImportedTab("https://left.example/"), kept),
            InSplit(ImportedTab("https://right.example/"), kept), InSplit(ImportedTab("https://broken-one.example/"), broken), moved);
        space["folders"] = new JsonArray(new JsonObject { ["id"] = SwiftId(group), ["title"] = "Research", ["location"] = "current" });
        space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = SwiftId(kept) }, new JsonObject { ["id"] = SwiftId(broken) });
        Reviewing(device, space);
        // Saving one tab of a split leaves its other tab on its own.
        device.Send(new PlaceImportTab(SpaceId(space), TabId(moved), TabPlacement.Saved));
        device.Send(new BeginImportCommit());

        device.Send(new ImportReviewedSpaces(device.Workspace, window));

        var grouped = device.Authority.Current.Spaces.Single(candidate => candidate.Settings.Name == "Grouped");
        var research = Assert.Single(grouped.Folders, folder => folder.Title == "Research");
        Assert.Equal(TabPlacement.Current, research.Location);
        Assert.Equal(["https://group-one.example/", "https://group-two.example/"],
            grouped.Tabs.Where(tab => tab.FolderId == research.Id).Select(tab => tab.Url));
        var split = Assert.Single(grouped.Tabs.Select(tab => tab.SplitGroupId).OfType<Guid>().Distinct());
        Assert.Equal(["https://left.example/", "https://right.example/"], grouped.Tabs.Where(tab => tab.SplitGroupId == split).Select(tab => tab.Url));
        Assert.All(grouped.Tabs.Where(tab => tab.Url!.Contains("broken", StringComparison.Ordinal)), tab => Assert.Null(tab.SplitGroupId));
        // The import counts as using the open tabs it brings, however long ago
        // the other browser last showed them, so cleanup leaves them open.
        Assert.All(grouped.Tabs.Where(tab => tab.Placement == TabPlacement.Current),
            tab => Assert.InRange(tab.LastActivatedAt, device.Clock.Now.AddMilliseconds(-1), device.Clock.Now.AddMilliseconds(1)));
    }

    [Fact]
    public void AReviewedSpaceJoiningAnotherBringsOnlyTheTabsItHasRoomFor() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!.AsObject();
        session.Remove("disposableSeedMarker");
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        int held = device.Authority.Current.Spaces.Single(space => space.Id == fixture.Space).Tabs.Count;
        int room = BrowserTabCollection.MaximumTabs - held;
        // A saved tab is the first to stay behind; an open one comes along.
        var joining = ImportedSpace("reading", [.. Enumerable.Range(0, room).Select(index => ImportedTab($"https://saved.example/{index}", "saved")),
            ImportedTab("https://open.example/")]);
        Reviewing(device, joining);
        device.Send(new BeginImportCommit());

        device.Send(new ImportReviewedSpaces(device.Workspace, window));

        var reading = device.Authority.Current.Spaces.Single(space => space.Id == fixture.Space);
        Assert.Equal(BrowserTabCollection.MaximumTabs, reading.Tabs.Count);
        Assert.Contains(reading.Tabs, tab => tab.Url == "https://open.example/");
        Assert.DoesNotContain(reading.Tabs, tab => tab.SavedUrl == $"https://saved.example/{room - 1}");
    }

    [Fact]
    public void AFileImportAddsItsSpacesWholeGivingCollidingRecordsNewIdentities() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var original = device.Authority.Current.Spaces[0];
        // The file holds this session's own Space, as an export of it does.
        var changes = device.Send(new ImportSpaces(device.Workspace, window, ReadSpaces(session["spaces"]![0]!)));

        var current = device.Authority.Current;
        Assert.Equal((original.Id, original.Tabs[0].Id, original.Folders[0].Id, original.History[0].Id),
            (current.Spaces[0].Id, current.Spaces[0].Tabs[0].Id, current.Spaces[0].Folders[0].Id, current.Spaces[0].History[0].Id));
        var imported = current.Spaces[1];
        Assert.NotEqual(original.Id, imported.Id);
        Assert.NotEqual(original.ProfileId, imported.ProfileId);
        Assert.Equal(original.Settings.Name, imported.Settings.Name);
        // Folder and history identities are global in sync, so the copy takes new ones.
        Assert.NotEqual(original.Folders[0].Id, imported.Folders[0].Id);
        Assert.NotEqual(original.History[0].Id, imported.History[0].Id);
        var tab = Assert.Single(imported.Tabs);
        Assert.NotEqual(original.Tabs[0].Id, tab.Id);
        Assert.Equal(imported.Folders[0].Id, tab.FolderId);
        // The imported tab wears the image of the tab it came from; the file
        // left the session's own tabs as they were.
        Assert.Equal([new ImportedTab(tab.Id, 0, original.Tabs[0].Id)], changes.OfType<TabsImported>().Single().Tabs);
        Assert.DoesNotContain(changes, change => change is TabCopied);
        // A file that fits beside a first launch's Spaces keeps them disposable.
        Assert.NotNull(current.DisposableSeedMarker);
        Assert.Equal((imported.Id, (Guid?)tab.Id), (device.Space(window), device.Tab(window, imported.Id)));

        // One that does not fit beside them takes their place, as a reviewed import does.
        var full = ReadSpaces([.. Enumerable.Range(0, SessionState.MaximumSpaces)
            .Select(index => ImportedSpace($"Many {index}", ImportedTab($"https://many.example/{index}")))]);
        device.Send(new ImportSpaces(device.Workspace, window, full));
        Assert.Equal((SessionState.MaximumSpaces, (Guid?)null), (device.Authority.Current.Spaces.Count,
            device.Authority.Current.DisposableSeedMarker));
    }

    [Fact]
    public void AReviewedImportJoinsTheSpaceItNamesAndMakesTheRestNewSpaces() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!.AsObject();
        session.Remove("disposableSeedMarker");
        var saved = session["spaces"]![0]!["tabs"]![0]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var folder = Guid.NewGuid();
        // Joins "Reading": its "articles" folder matches the Space's "Articles",
        // and pinned tabs past the limit move to the overflow folder.
        var pinned = Enumerable.Range(0, TabPlacement.PinnedCapacity + 1)
            .Select(index => ImportedTab($"https://pin.example/{index}", "pinned")).ToArray();
        var joining = ImportedSpace("reading",
            [ImportedTab("https://example.com/article#one"), ImportedTab("https://new.example/", "saved", folder), .. pinned]);
        joining["folders"] = new JsonArray(new JsonObject { ["id"] = SwiftId(folder), ["title"] = " articles ", ["location"] = "saved" },
            new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["title"] = "Unused", ["location"] = "saved" });
        var moved = ImportedTab("https://moved.example/");
        var fresh = ImportedSpace("Travel", moved, ImportedTab("https://left.example/"));
        var dropped = ImportedSpace("Dropped", ImportedTab("https://dropped.example/"));
        // The review joins "Reading" and leaves out the tab it holds.
        var review = Reviewing(device, joining, fresh, dropped);
        Assert.Equal(fixture.Space, review.Spaces[0].DestinationId);
        Assert.Equal(joining["tabs"]!.AsArray().Skip(1).Select(tab => TabId(tab!)), review.Spaces[0].IncludedTabIds);
        device.Send(new CustomizeImportSpace(SpaceId(fresh), Customization("Trips")));
        device.Send(new IncludeImportTabs(SpaceId(fresh), [TabId(fresh["tabs"]![1]!)], Included: false));
        device.Send(new PlaceImportTab(SpaceId(fresh), TabId(moved), TabPlacement.Pinned));
        device.Send(new IncludeImportSpace(SpaceId(dropped), Included: false));
        device.Send(new BeginImportCommit());

        var changes = device.Send(new ImportReviewedSpaces(device.Workspace, window));

        var current = device.Authority.Current;
        Assert.Equal(2, current.Spaces.Count);
        var reading = current.Spaces[0];
        Assert.Equal(fixture.Space, reading.Id);
        Assert.Equal(TabId(saved), reading.Tabs[0].Id);
        var overflow = reading.Folders.Single(candidate => candidate.Title == NativeWorkspaceImport.OverflowFolderTitle);
        Assert.Equal(2, reading.Folders.Count);
        Assert.Equal(reading.Folders[0].Id, reading.Tabs.Single(tab => tab.Url == "https://new.example/").FolderId);
        Assert.Equal(TabPlacement.PinnedCapacity, reading.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        Assert.Equal(overflow.Id, reading.Tabs.Single(tab => tab.Url == $"https://pin.example/{TabPlacement.PinnedCapacity}").FolderId);
        var trips = current.Spaces[1];
        Assert.Equal("Trips", trips.Settings.Name);
        var pinnedTrip = Assert.Single(trips.Tabs);
        Assert.Equal((TabId(moved), TabPlacement.Pinned, TabPlacement.Pinned.ImportedSymbol, "https://moved.example/"),
            (pinnedTrip.Id, pinnedTrip.Placement, pinnedTrip.Symbol, pinnedTrip.SavedUrl));
        Assert.Contains(new ImportedTab(TabId(moved), 1, TabId(moved)), changes.OfType<TabsImported>().Single().Tabs);
        Assert.Equal(reading.Id, device.Space(window));
        Assert.Equal(TabId(moved), device.Tab(window, trips.Id));
        // An import asked for from the app ends on what it did.
        var finished = Flowing(device.Send(new FinishImportCommit()));
        Assert.Equal((ImportStep.Complete, new ImportSummary(TabCount: 15, SpaceCount: 2)),
            (finished.Step, finished.Summary));
    }

    [Fact]
    public void AnImportIsOnDiskWithItsJournalBeforeItReturnsOrNothingChanges() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var answered = app.Send(Adoption(document));
        var (workspace, opened) = TestWorkspaces.OpenStored(app);
        var session = app.Workspace(workspace);
        var sync = app.StoredSync!;
        sync.Flush();
        _ = DrainLaunch(app, [.. answered, .. opened]);
        var import = new ImportSpaces(workspace, Guid.NewGuid(), ReadSpaces(ImportedSpace("Imported", ImportedTab("https://imported.example/"))));
        var (stored, staged, kept) = (StoredParts(directory.File), sync.Snapshot, session.Current);

        RefuseWrites(directory.File, "journal");
        Assert.IsType<SaveFailed>(Assert.Throws<Rejected>(() => app.Send(import)).Rejection);
        Assert.Same(kept, session.Current);
        Assert.Same(staged, sync.Snapshot);
        AssertSameParts(stored, StoredParts(directory.File));

        AcceptWrites(directory.File);
        app.Send(import);
        Assert.Equal(2, session.Current.Spaces.Count);
        var parts = StoredParts(directory.File);
        Assert.True(parts["core"].AsSpan().SequenceEqual(session.Checkpoint().Read("core")));
        Assert.True(parts["journal"].AsSpan().SequenceEqual(sync.Snapshot.Read()));
    }

}
