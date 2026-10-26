using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Reading other browsers' sessions: what each brings of its Spaces, windows,
/// pinned and saved tabs, folders and looks, the one way every browser's tabs
/// are cleaned, and the refusal that names what is wrong with a file Crest
/// cannot read.
public sealed partial class BrowserContractsTests {
    private static readonly DateTimeOffset ImportedAt = new(2026, 9, 26, 12, 0, 0, TimeSpan.Zero);

    /// The path of `file` in the import fixture `name`.
    private static string ImportFixture(string name, string file) =>
        Path.Combine(AppContext.BaseDirectory, "Portability", "Fixtures", name, file);

    /// An app that reads imports at `ImportedAt`, naming unnamed Spaces with
    /// the texts the platform resolved.
    private static CrestApp Importer(params ImportSpaceNames[] names) =>
        new(new AppConfiguration(null, DevicePlatform.Desktop, names.Length == 0 ? null : names), new TestClock(ImportedAt), new TestIds());

    /// What `source` reads from the session file `file` of fixture `name`, as
    /// the only file of a profile named "Profile".
    private static IReadOnlyList<SpaceState> ReadSession(string source, string name, string file, params ImportSpaceNames[] names) {
        using var app = Importer(names);
        return app.Query(new ReadImport(ImportSource.Named(source)!, [new("profile", "Profile", null, ImportFixture(name, file))])).Spaces;
    }

    /// A Space's tabs in order, each with its placement, address and the title
    /// of the folder holding it.
    private static (string Title, TabPlacement Placement, string? Url, string? Folder)[] TabsOf(SpaceState space) =>
        [.. space.Tabs.Select(tab => (tab.Title, tab.Placement, tab.Url, space.Folders.FirstOrDefault(folder => folder.Id == tab.FolderId)?.Title))];

    /// A Space's folders in order, each with the title of its parent.
    private static (string Title, string? Parent)[] FoldersOf(SpaceState space) =>
        [.. space.Folders.Select(folder => (folder.Title, space.Folders.FirstOrDefault(parent => parent.Id == folder.ParentId)?.Title))];

    [Fact]
    public void ArcBringsEachSpacesFavoritesTodayAndPinnedFoldersWithItsIconAndLook() {
        var spaces = ReadSession("arc", "arc-rich", "StorableSidebar.json");

        Assert.Equal(["Arc Work", "Gradient", "Single"], spaces.Select(space => space.Settings.Name));
        var work = spaces[0];
        Assert.Equal(("crest.emoji:🏛️", SpaceAccent.Indigo), (work.Settings.Symbol, work.Settings.Accent));
        // Favorites are pinned, Today's tabs stay open whatever lists hold them,
        // and pinned lists become saved folders. A file address is dropped.
        Assert.Equal([
            ("Favorite", TabPlacement.Pinned, "https://favorite.example/", null),
            ("Today", TabPlacement.Current, "https://today.example/", null),
            ("today-two.example", TabPlacement.Current, "https://today-two.example/path", null),
            ("Saved", TabPlacement.Saved, "https://saved.example/", "Reading"),
            ("Deep title", TabPlacement.Saved, "https://deep.example/", "Untitled Folder")
        ], TabsOf(work));
        Assert.Equal([("Reading", null), ("Untitled Folder", "Reading")], FoldersOf(work));

        // Another profile's favorites are its own; a gradient keeps its colors
        // the way Crest can draw them.
        var gradient = spaces[1];
        Assert.Equal(("chevron.left.forwardslash.chevron.right", SpaceAccent.Orange), (gradient.Settings.Symbol, gradient.Settings.Accent));
        Assert.Equal([TabPlacement.Pinned, TabPlacement.Pinned], gradient.Tabs.Select(tab => tab.Placement));
        Assert.Equal((SpaceBannerPattern.Diagonal, SpaceThemeMode.Gradient, 3),
            (gradient.Settings.Branding!.BannerPattern, gradient.Settings.Branding.ThemeMode, gradient.Settings.Branding.Colors.Colors.Count));
        Assert.Equal(("globe.americas.fill", SpaceAccent.Teal), (spaces[2].Settings.Symbol, spaces[2].Settings.Accent));
    }

    [Fact]
    public void ZenBringsItsSpacesWithTheirEssentialsFoldersAndThemes() {
        var spaces = ReadSession("zen", "zen-rich", Path.Combine("profile", "zen-sessions.jsonlz4"));

        // A Space without an identity holds nothing and is skipped.
        Assert.Equal(["Zen Work", "Zen Space 2"], spaces.Select(space => space.Settings.Name));
        var work = spaces[0];
        // Essentials are pinned, one no Space claims is pinned in every Space,
        // pinned tabs are saved, and an open tab shows its current entry.
        Assert.Equal([
            ("Essential", TabPlacement.Pinned, "https://essential.example/", null),
            ("Shared Essential", TabPlacement.Pinned, "https://shared.example/", null),
            ("Saved", TabPlacement.Saved, "https://saved.example/", "Inner"),
            ("Open", TabPlacement.Current, "https://open.example/", null)
        ], TabsOf(work));
        Assert.Equal([("Reading", null), ("Inner", "Reading")], FoldersOf(work));
        var theme = work.Settings.Branding!;
        Assert.Equal((SpaceBannerPattern.Bands, SpaceThemeMode.Gradient, 3, 0.4, true),
            (theme.BannerPattern, theme.ThemeMode, theme.Colors.Colors.Count, theme.BannerStrength, theme.ShowsTexture));
        Assert.Equal(["Shared Essential", "Play"], spaces[1].Tabs.Select(tab => tab.Title));
        Assert.Equal(SpaceAccent.Orange, spaces[1].Settings.Accent);
    }

    [Fact]
    public void PinnedTabsPastWhatCrestPinsAreSavedInAFolderOfTheirOwn() {
        var space = Assert.Single(ReadSession("zen", "zen-overflow", Path.Combine("profile", "zen-sessions.jsonlz4")));

        Assert.Equal(TabPlacement.PinnedCapacity, space.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        var overflow = Assert.Single(space.Folders);
        Assert.Equal(("Imported Pinned Tabs", "pin.slash", TabPlacement.Saved), (overflow.Title, overflow.Symbol, overflow.Location));
        Assert.Equal(["Pin 13", "Pin 14"], space.Tabs.Where(tab => tab.FolderId == overflow.Id).Select(tab => tab.Title));
    }

    [Fact]
    public void ChromiumFirefoxAndSafariSessionsBringEachWindowsTabsInOrder() {
        // Chromium restores each tab's current entry and its pinned state from
        // the command log, and drops what a later command removed.
        Assert.Equal([
            ("Other Window", TabPlacement.Current, "https://example.org/", null),
            ("Current", TabPlacement.Pinned, "https://chromium.org/current#anchor", null)
        ], TabsOf(Assert.Single(ReadSession("chrome", "chromium-windows", Path.Combine("Sessions", "Session_1")))));
        Assert.Equal([("Second", TabPlacement.Current, "http://second.example/", null), ("Page 4", TabPlacement.Current, "https://prune.example/4", null)],
            TabsOf(Assert.Single(ReadSession("chrome", "chromium-pruned", Path.Combine("Sessions", "Session_2")))));

        // Firefox reads the same whether its file is compressed or not.
        (string, TabPlacement, string?, string?)[] firefox = [
            ("Selected Tab", TabPlacement.Current, "https://selected.example/", null),
            ("One", TabPlacement.Current, "https://one.example/", null),
            ("Two", TabPlacement.Pinned, "https://two.example/", null),
            ("Clamped", TabPlacement.Current, "https://clamped.example/", null)
        ];
        Assert.Equal(firefox, TabsOf(Assert.Single(ReadSession("firefox", "firefox-lz4", Path.Combine("profile", "sessionstore.jsonlz4")))));
        Assert.Equal(firefox, TabsOf(Assert.Single(ReadSession("firefox", "firefox-plain", Path.Combine("profile", "recovery.jsonlz4")))));

        Assert.Equal([
            ("One", TabPlacement.Current, "https://example.com/one#section", null),
            ("WebKit", TabPlacement.Pinned, "https://webkit.org/", null),
            ("Nested", TabPlacement.Current, "https://nested.example/", null),
            ("Safari", TabPlacement.Current, "https://developer.apple.com/safari/", null)
        ], TabsOf(Assert.Single(ReadSession("safari", "safari-windows", "LastSession.plist"))));
        Assert.Equal([("A", TabPlacement.Current, "https://loose.example/a", null), ("loose.example", TabPlacement.Current, "https://loose.example/b", null)],
            TabsOf(Assert.Single(ReadSession("safari", "safari-loose", "LastSession.plist"))));
    }

}
