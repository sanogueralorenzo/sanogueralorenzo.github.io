using System.Text;
using System.Text.RegularExpressions;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Crest's own browser-data file and the bookmark file an export writes:
/// every version reads with identities of its own, an export reads back as
/// the workspace it wrote without what stays on the device, a locked Space
/// keeps both exports from being written, and a file that breaks a rule is
/// refused before anything is made of it.
public sealed partial class BrowserContractsTests {
    /// The Spaces the browser-data file at `path` holds.
    private static IReadOnlyList<SpaceState> ReadBrowserData(string path) {
        using var app = Importer();
        return app.Query(new ReadArchive(path)).Spaces;
    }

    /// Every identity `space` holds.
    private static IEnumerable<Guid> IdentitiesOf(SpaceState space) => [
        space.Id, space.ProfileId, .. space.Folders.Select(folder => folder.Id), .. space.Tabs.Select(tab => tab.Id),
        .. space.SplitGroups.Select(split => split.Id), .. space.ArchivedTabs.Select(archived => archived.Tab.Id),
        .. space.History.Select(entry => entry.Id)
    ];

    [Fact]
    public void ABrowserDataFileOfEveryVersionReadsWithIdentitiesOfItsOwn() {
        string path = ImportFixture("archive-current", "data.json");
        var space = Assert.Single(ReadBrowserData(path));

        Assert.Equal(("Portable Work", "briefcase.fill", SpaceAccent.Teal), (space.Settings.Name, space.Settings.Symbol, space.Settings.Accent));
        Assert.Equal((StoredSessionCodec.DefaultCredentialPreferences, SpaceAccessPolicy.Open),
            (space.Settings.CredentialPreferences, space.Settings.AccessPolicy));
        Assert.Equal([("Research", null), ("WebKit", "Research")], FoldersOf(space));
        Assert.Equal([
            ("Private URL", TabPlacement.Pinned, "https://example.com/private#section", null),
            ("Reference", TabPlacement.Saved, "https://developer.apple.com/documentation/webkit", "WebKit"),
            ("Start Page", TabPlacement.Current, null, null),
            ("Settings", TabPlacement.Current, null, null)
        ], TabsOf(space));
        Assert.Equal([null, null, null, "settings"], space.Tabs.Select(tab => tab.NativeContent?.Kind));
        Assert.Equal(["Closed"], space.ArchivedTabs.Select(archived => archived.Tab.Title));
        Assert.Equal([("https://example.com/history", 4)], space.History.Select(entry => (entry.Url, entry.VisitCount)));

        // Nothing keeps an identity the file spelled, and each read makes new ones.
        var written = Regex.Matches(File.ReadAllText(path), "[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}").Select(match => Guid.Parse(match.Value));
        Assert.Empty(IdentitiesOf(space).Intersect(written));
        Assert.Empty(IdentitiesOf(space).Intersect(IdentitiesOf(Assert.Single(ReadBrowserData(path)))));

        // The first version kept every folder at the top level; the second had
        // no split groups.
        Assert.Equal([("Research", null), ("WebKit", null)], FoldersOf(Assert.Single(ReadBrowserData(ImportFixture("archive-version-one", "data.json")))));
        Assert.Equal(TabsOf(space), TabsOf(Assert.Single(ReadBrowserData(ImportFixture("archive-version-two", "data.json")))));
        // One address visited under two entries is one entry of the newer title.
        Assert.Equal([("Newer title", 6)],
            Assert.Single(ReadBrowserData(ImportFixture("archive-duplicate-history", "data.json"))).History.Select(entry => (entry.Title, entry.VisitCount)));
        // A Space without tabs opens on a Start Page.
        var empty = Assert.Single(Assert.Single(ReadBrowserData(ImportFixture("archive-no-tabs", "data.json"))).Tabs);
        Assert.Equal((TabPlacement.Current, null, null), (empty.Placement, empty.Url, empty.NativeContent));

        var split = Assert.Single(ReadBrowserData(ImportFixture("archive-split", "data.json")));
        var group = Assert.Single(split.SplitGroups);
        Assert.Equal([group.Id, group.Id], split.Tabs.Select(tab => tab.SplitGroupId));
        Assert.Equal(("Portable Pair", "crest.emoji:👨🏽‍💻"), (group.CustomTitle, group.CustomIconSymbol));
    }

    [Theory]
    [InlineData("archive-foreign", typeof(NotAnArchive))]
    [InlineData("archive-future", typeof(UnsupportedArchiveVersion))]
    [InlineData("archive-not-json", typeof(ArchiveInvalid))]
    [InlineData("archive-wrong-type", typeof(ArchiveInvalid))]
    [InlineData("archive-empty-spaces", typeof(ArchiveInvalid))]
    [InlineData("archive-cyclic-folders", typeof(ArchiveInvalid))]
    [InlineData("archive-unknown-folder", typeof(ArchiveInvalid))]
    [InlineData("archive-too-many-pinned", typeof(ArchiveInvalid))]
    [InlineData("archive-uncanonical-url", typeof(ArchiveInvalid))]
    [InlineData("archive-missing", typeof(FileUnreadable))]
    public void ABrowserDataFileThatBreaksARuleIsRefusedBeforeAnythingIsMadeOfIt(string name, Type refusal) =>
        Assert.IsType(refusal, Assert.Throws<Rejected>(() => ReadBrowserData(ImportFixture(name, "data.json"))).Rejection);

    [Fact]
    public void AnExportReadsBackAsTheWorkspaceItWroteWithoutWhatStaysOnTheDevice() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var window = device.Showing(session);
        var files = ReadBrowserData(ImportFixture("archive-current", "data.json"))
            .Concat(ReadBrowserData(ImportFixture("archive-split", "data.json"))).ToArray();
        device.Send(new ImportSpaces(device.Workspace, window, files));

        var exported = device.Query(new ExportWorkspace(device.Workspace, ExportFormat.BrowserData));
        string text = Encoding.UTF8.GetString(exported.Contents);
        using var folder = new BrowserDataFolder();
        var spaces = ReadBrowserData(folder.Write(ExportFormat.BrowserData.FileName, text));

        Assert.Equal(ExportFormat.BrowserData, exported.Format);
        Assert.Contains("com.pauldavis.crest.browser-data", text, StringComparison.Ordinal);
        // Credentials, locks, profiles, icons and loaded pages stay on the device.
        Assert.All(new[] { "credentialPreferences", "accessPolicy", "\"profile", "faviconURL", "iconAccent", "keepsPageLoaded" },
            key => Assert.DoesNotContain(key, text, StringComparison.Ordinal));
        var current = device.Authority.Current.Spaces;
        Assert.Equal(current.Select(space => space.Settings.Name), spaces.Select(space => space.Settings.Name));
        for (int index = 0; index < current.Count; index++) {
            Assert.Equal(TabsOf(current[index]), TabsOf(spaces[index]));
            Assert.Equal(FoldersOf(current[index]), FoldersOf(spaces[index]));
            Assert.Equal(current[index].History.Select(entry => (entry.Url, entry.Title, entry.VisitCount)),
                spaces[index].History.Select(entry => (entry.Url, entry.Title, entry.VisitCount)));
            Assert.Equal(current[index].ArchivedTabs.Select(archived => archived.Tab.Title), spaces[index].ArchivedTabs.Select(archived => archived.Tab.Title));
            Assert.Equal(current[index].SplitGroups.Select(split => (split.CustomTitle, split.CustomIconSymbol)),
                spaces[index].SplitGroups.Select(split => (split.CustomTitle, split.CustomIconSymbol)));
            Assert.Equal(current[index].Settings.Look, spaces[index].Settings.Look);
        }
    }

    [Fact]
    public void OpenTabFoldersKeepTheirNestingContentsAndPlaceThroughAFile() {
        var session = SavedSession().Document["session"]!;
        var space = session["spaces"]![0]!;
        Guid root = Guid.NewGuid(), child = Guid.NewGuid(), after = Guid.NewGuid();
        space["folders"]!.AsArray().Add(new System.Text.Json.Nodes.JsonObject {
            ["id"] = SwiftId(root),
            ["title"] = "Root",
            ["location"] = "current"
        });
        space["folders"]!.AsArray().Add(new System.Text.Json.Nodes.JsonObject {
            ["id"] = SwiftId(child),
            ["title"] = "Child",
            ["location"] = "current",
            ["parentID"] = SwiftId(root)
        });
        // An empty folder keeps its place before the tab it is anchored to.
        space["folders"]!.AsArray().Add(new System.Text.Json.Nodes.JsonObject {
            ["id"] = SwiftId(Guid.NewGuid()),
            ["title"] = "Before",
            ["location"] = "current",
            ["orderAnchorTabID"] = SwiftId(after)
        });
        space["tabs"]!.AsArray().Add(new System.Text.Json.Nodes.JsonObject {
            ["id"] = SwiftId(Guid.NewGuid()),
            ["title"] = "Inside",
            ["url"] = "https://inside.example/",
            ["placement"] = "current",
            ["folderID"] = SwiftId(child),
            ["lastActivatedAt"] = 800000000.0
        });
        space["tabs"]!.AsArray().Add(new System.Text.Json.Nodes.JsonObject {
            ["id"] = SwiftId(after),
            ["title"] = "After",
            ["url"] = "https://after.example/",
            ["placement"] = "current",
            ["lastActivatedAt"] = 800000000.0
        });
        using var device = new TestDevice(session);
        using var folder = new BrowserDataFolder();

        var exported = device.Query(new ExportWorkspace(device.Workspace, ExportFormat.BrowserData));
        var read = Assert.Single(ReadBrowserData(folder.Write(ExportFormat.BrowserData.FileName, Encoding.UTF8.GetString(exported.Contents))));

        Assert.Equal(FoldersOf(device.Authority.Current.Spaces[0]), FoldersOf(read));
        Assert.Contains(("Child", "Root"), FoldersOf(read));
        Assert.All(read.Folders.Where(entry => entry.Title != "Articles"), entry => Assert.Equal(TabPlacement.Current, entry.Location));
        Assert.Contains(("Inside", TabPlacement.Current, "https://inside.example/", "Child"), TabsOf(read));
        Assert.Equal(read.Tabs.Single(tab => tab.Title == "After").Id, read.Folders.Single(entry => entry.Title == "Before").OrderAnchorTabId);
    }

    [Fact]
    public void BookmarksAreExportedInTheStandardFormatWithoutOpenTabs() {
        var session = SavedSession().Document["session"]!;
        var tabs = session["spaces"]![0]!["tabs"]!.AsArray();
        tabs[0]!["title"] = "A < B & \"C\"";
        tabs.Add(new System.Text.Json.Nodes.JsonObject {
            ["id"] = SwiftId(Guid.NewGuid()),
            ["title"] = "Open",
            ["url"] = "https://current.example/",
            ["placement"] = "current",
            ["lastActivatedAt"] = 800000000.0
        });
        using var device = new TestDevice(session);

        var exported = device.Query(new ExportWorkspace(device.Workspace, ExportFormat.Bookmarks));
        string html = Encoding.UTF8.GetString(exported.Contents);

        Assert.StartsWith("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n", html, StringComparison.Ordinal);
        Assert.Contains("CREST_SPACE=\"true\">Reading</H3>", html, StringComparison.Ordinal);
        Assert.Contains("<DT><H3>Articles</H3>", html, StringComparison.Ordinal);
        // A saved tab is written as its saved address and its page's title.
        Assert.Contains("HREF=\"https://example.com/\"", html, StringComparison.Ordinal);
        Assert.Contains(">A &lt; B &amp; &quot;C&quot;</A>", html, StringComparison.Ordinal);
        Assert.DoesNotContain("current.example", html, StringComparison.Ordinal);
    }

    [Fact]
    public void AnExportIsRefusedWhileASpaceIsLockedAndWrittenOnceItIsOpen() {
        var session = GuardedSession();
        using var device = new TestDevice(session);

        foreach (var format in ExportFormat.All)
            Assert.IsType<SpaceLocked>(Assert.Throws<Rejected>(() => device.Query(new ExportWorkspace(device.Workspace, format))).Rejection);

        Unlock(device.Send, device.Workspace, Identity(session).Space);
        foreach (var format in ExportFormat.All)
            Assert.NotEmpty(device.Query(new ExportWorkspace(device.Workspace, format)).Contents);
    }
}
