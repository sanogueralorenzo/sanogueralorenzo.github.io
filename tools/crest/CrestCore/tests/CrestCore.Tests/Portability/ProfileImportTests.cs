using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Finding what another browser keeps in the data folder the person chose,
/// and reading a profile's bookmarks and open tabs together into one Space
/// that keeps whatever of them could be read.
public sealed partial class BrowserContractsTests {
    /// A browser's data folder the test builds, removed with everything in it.
    private sealed class BrowserDataFolder : IDisposable {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "crest-import-" + Guid.NewGuid().ToString("N"));

        public BrowserDataFolder() => Directory.CreateDirectory(Path);

        /// Writes `contents` to `name` inside the folder, last changed at
        /// `changed` seconds since 1970, and answers its path.
        public string Write(string name, string contents = "", long changed = 1_000) {
            string file = System.IO.Path.Combine(Path, name);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file)!);
            File.WriteAllBytes(file, Encoding.UTF8.GetBytes(contents));
            File.SetLastWriteTimeUtc(file, DateTime.UnixEpoch.AddSeconds(changed));
            return file;
        }

        /// Copies the file at `source` to `name` inside the folder, last
        /// changed at `changed` seconds since 1970, and answers its path.
        public string Copy(string source, string name, long changed = 1_000) {
            string file = System.IO.Path.Combine(Path, name);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file)!);
            File.Copy(source, file);
            File.SetLastWriteTimeUtc(file, DateTime.UnixEpoch.AddSeconds(changed));
            return file;
        }

        public void Dispose() => Directory.Delete(Path, recursive: true);
    }

    /// A Chrome bookmark file holding a link to each of `links`, named for
    /// it, in its bookmarks bar.
    private static string Bar(params string[] links) => new JsonObject {
        ["roots"] = new JsonObject {
            ["bookmark_bar"] = new JsonObject {
                ["type"] = "folder",
                ["name"] = "Bar",
                ["children"] = new JsonArray([.. links.Select(link => (JsonNode)new JsonObject {
                    ["type"] = "url",
                    ["name"] = link,
                    ["url"] = $"https://{link}.example/"
                })])
            }
        }
    }.ToJsonString();

    private static ImportData Found(ImportSource source, string folder) {
        using var app = Importer();
        return app.Query(new FindImportData(source, folder));
    }

    [Fact]
    public void AProfileBringsItsBookmarksAndOpenTabsAsOneSpaceNamedForIt() {
        string root = ImportFixture("chrome-profile", "");
        using var app = Importer();
        var spaces = app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Personal", Path.Combine(root, "Default", "Bookmarks"), Path.Combine(root, "Default", "Sessions", "Session_1")),
            new("Profile 1", "Work", null, Path.Combine(root, "Profile 1", "Sessions", "Session_1")),
            new("Profile 2", "Locked", Path.Combine(root, "Profile 2", "Bookmarks"), Path.Combine(root, "Profile 2", "Sessions", "Session_1"))
        ])).Spaces;

        Assert.Equal(["Personal", "Work", "Locked"], spaces.Select(space => space.Settings.Name));
        Assert.All(spaces, space => Assert.Equal(("globe", SpaceAccent.Orange), (space.Settings.Symbol, space.Settings.Accent)));
        // Every bookmark root holding a link becomes a folder, the named ones
        // after Chrome's own in the order of their keys; an empty root, as
        // Mobile bookmarks is here, makes none, and a browser page is dropped.
        Assert.Equal([
            ("Bookmarks bar", null), ("Other bookmarks", null), ("Reference", "Other bookmarks"), ("Untitled Folder", "Other bookmarks"),
            ("Alpha root", null), ("Zeta root", null)
        ], FoldersOf(spaces[0]));
        Assert.Equal([
            ("Chromium", TabPlacement.Saved, "https://www.chromium.org/", "Bookmarks bar"),
            ("untitled.example", TabPlacement.Saved, "https://untitled.example/path", "Bookmarks bar"),
            ("WebKit", TabPlacement.Saved, "https://webkit.org/", "Reference"),
            ("Alpha", TabPlacement.Saved, "https://alpha.example/", "Alpha root"),
            ("Zeta", TabPlacement.Saved, "https://zeta.example/", "Zeta root"),
            ("Open", TabPlacement.Pinned, "https://open.example/", null),
            ("Second", TabPlacement.Current, "https://second.example/", null)
        ], TabsOf(spaces[0]));
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_725_526_400), spaces[0].Tabs[0].LastActivatedAt);
        Assert.Equal(["Open", "Second"], spaces[1].Tabs.Select(tab => tab.Title));
        // A profile-encrypted session leaves the profile its bookmarks.
        Assert.DoesNotContain(spaces[2].Tabs, tab => tab.Placement != TabPlacement.Saved);
        Assert.Equal(5, spaces[2].Tabs.Count);
    }

    [Fact]
    public void SafariBookmarksKeepTheirFoldersAndEachDateUnitSafariWrote() {
        string root = ImportFixture("safari-profile", "");
        using var app = Importer();
        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Safari, [
            new("safari", "Safari", Path.Combine(root, "Bookmarks.plist"), Path.Combine(root, "LastSession.plist"))
        ])).Spaces);

        Assert.Equal([("Favorites", null), ("Empty", null)], FoldersOf(space));
        Assert.Equal([
            ("Safari", TabPlacement.Saved, "https://developer.apple.com/safari/", "Favorites"),
            ("seconds.example", TabPlacement.Saved, "https://seconds.example/", "Favorites"),
            ("micro.example", TabPlacement.Saved, "https://micro.example/", "Favorites"),
            ("Top", TabPlacement.Saved, "https://top.example/", null),
            ("Open", TabPlacement.Current, "https://open.safari.example/", null)
        ], TabsOf(space));
        Assert.All(space.Tabs.Take(3), tab => Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_600_000_000), tab.LastActivatedAt));
    }

    [Fact]
    public void AProfileKeepsWhateverCouldBeReadAndIsRefusedOnlyWhenNothingCould() {
        using var app = Importer();
        string safari = ImportFixture("safari-bad-bookmarks", "");
        var openTabs = Assert.Single(app.Query(new ReadImport(ImportSource.Safari, [
            new("safari", "Safari", Path.Combine(safari, "Bookmarks.plist"), Path.Combine(safari, "LastSession.plist"))
        ])).Spaces);
        Assert.Equal([("Open", TabPlacement.Current, "https://open.safari.example/", null)], TabsOf(openTabs));

        // A profile that brings nothing is left out with the last thing that
        // went wrong, and one that comes without its open tabs says why,
        // while the others come.
        string root = ImportFixture("chrome-profile", "");
        string broken = ImportFixture("chrome-broken-both", "Default");
        var read = app.Query(new ReadImport(ImportSource.Chrome, [
            new("Profile 1", "Work", null, Path.Combine(root, "Profile 1", "Sessions", "Session_1")),
            new("Default", "Broken", Path.Combine(broken, "Bookmarks"), Path.Combine(broken, "Sessions", "Session_1")),
            new("Profile 2", "Locked", Path.Combine(root, "Profile 2", "Bookmarks"), Path.Combine(root, "Profile 2", "Sessions", "Session_1"))
        ]));
        Assert.Equal(["Work", "Locked"], read.Spaces.Select(space => space.Settings.Name));
        Assert.Equal([new ImportLeftOut("Broken", new SessionEncrypted()), new ImportLeftOut("Locked", new SessionEncrypted())], read.LeftOut);

        // Nothing read: the refusal is the last thing that went wrong.
        Assert.IsType<SessionEncrypted>(Assert.Throws<Rejected>(() => app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Personal", Path.Combine(broken, "Bookmarks"), Path.Combine(broken, "Sessions", "Session_1"))
        ]))).Rejection);
        // Bookmarks nested deeper than a folder can be are left out, and with
        // nothing else to bring the profile is refused with why.
        Assert.IsType<BookmarksOverLimits>(Assert.Throws<Rejected>(() => app.Query(new ReadImport(ImportSource.Chrome, [
            new("Default", "Personal", ImportFixture("chrome-deep", Path.Combine("Default", "Bookmarks")), null)
        ]))).Rejection);
    }

    [Fact]
    public void ASignedInChromeProfileBringsItsAccountsBookmarksAndPasswordsToo() {
        using var chrome = new BrowserDataFolder();
        // The account's bookmarks join the profile's own, without repeating
        // one the same folder already holds.
        string own = chrome.Write(Path.Combine("Default", "Bookmarks"), Bar("a", "b"));
        chrome.Write(Path.Combine("Default", "AccountBookmarks"), Bar("b", "c"));
        string ownStore = chrome.Write(Path.Combine("Default", "Login Data"));
        string accountStore = chrome.Write(Path.Combine("Default", "Login Data For Account"));
        // A profile may keep only its account's bookmarks; what it deleted, as Vivaldi keeps it, stays behind.
        string accountOnly = chrome.Write(Path.Combine("Profile 1", "AccountBookmarks"), """
            {"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"d","url":"https://d.example/"}]},
              "trash":{"type":"folder","name":"Trash","children":[{"type":"url","name":"x","url":"https://deleted.example/"}]}}}
            """);

        var found = Found(ImportSource.Chrome, chrome.Path);
        Assert.Equal([own, accountOnly], found.Profiles.Select(profile => profile.BookmarksPath));
        Assert.Equal([new ImportPasswordStore("Default", "Personal", ownStore), new ImportPasswordStore("Default", "Personal", accountStore)],
            found.PasswordStores);
        using var app = Importer();
        var spaces = app.Query(new ReadImport(ImportSource.Chrome, found.Profiles)).Spaces;

        Assert.Equal([
            ("a", TabPlacement.Saved, "https://a.example/", "Bar"),
            ("b", TabPlacement.Saved, "https://b.example/", "Bar"),
            ("c", TabPlacement.Saved, "https://c.example/", "Bar")
        ], TabsOf(spaces[0]));
        Assert.Equal([("Bar", null)], FoldersOf(spaces[0]));
        Assert.Equal(["https://d.example/"], spaces[1].Tabs.Select(tab => tab.Url));
    }
}
