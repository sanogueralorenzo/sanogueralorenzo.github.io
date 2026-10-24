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
    public void ArcReadsEitherSidebarShapeKeepsTheLaterOfTwoItemsWithOneIdAndReadsBothTimeUnits() {
        var shapes = Assert.Single(ReadSession("arc", "arc-shapes", "StorableSidebar.json"));
        Assert.Equal("Work", shapes.Settings.Name);
        Assert.Equal([("Current", TabPlacement.Current, "https://current.example/", null)], TabsOf(shapes));

        var duplicate = Assert.Single(ReadSession("arc", "arc-duplicate", "StorableSidebar.json"));
        Assert.Equal(["https://current.example/"], duplicate.Tabs.Select(tab => tab.Url));

        // Arc stored seconds, and later milliseconds, since 1970.
        var times = Assert.Single(ReadSession("arc", "arc-simple", "StorableSidebar.json")).Tabs.Select(tab => tab.LastActivatedAt).ToArray();
        Assert.All(times, time => Assert.InRange(time, DateTimeOffset.FromUnixTimeSeconds(1_700_000_000).AddMilliseconds(-1),
            DateTimeOffset.FromUnixTimeSeconds(1_700_000_000).AddMilliseconds(124)));
    }

    [Fact]
    public void UnnamedSpacesAndWindowsTakeTheNumberedNameThePlatformResolved() {
        var names = new ImportSpaceNames(ImportSource.Arc, "Arc-Tabs", "Arc-Bereich %lld");

        // A blank title takes the numbered name for its place; a Space without
        // one keeps Arc's own name for it, and a named Space without tabs
        // comes empty.
        Assert.Equal(["Arc-Bereich 1", "Arc Space 2", "Empty", "Arc-Bereich 4"],
            ReadSession("arc", "arc-unnamed", "StorableSidebar.json", names).Select(space => space.Settings.Name));
        // An older Arc keeps Chromium's session, whose windows are numbered.
        var windows = ReadSession("arc", "arc-snss", "StorableSidebar.json", names);
        Assert.Equal(["Arc-Bereich 2", "Arc-Bereich 1"], windows.Select(space => space.Settings.Name));
        Assert.Equal("Imported Arc Space 1", ReadSession("arc", "arc-snss", "StorableSidebar.json")[1].Settings.Name);
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
    public void ZenSplitViewsComeAsSplitsSavedInTheFolderHoldingThem() {
        // Zen keeps each split view as a group of its own: one inside a folder
        // among the folders, naming no Space, and one among the pinned tabs
        // only among its groups.
        var space = Assert.Single(ReadSession("zen", "zen-splits", Path.Combine("profile", "zen-sessions.jsonlz4")));

        Assert.Equal([
            ("Essential", TabPlacement.Pinned, "https://essential.example/", null),
            ("Split Left", TabPlacement.Saved, "https://left.example/", null),
            ("Split Right", TabPlacement.Saved, "https://right.example/", null),
            ("Doc", TabPlacement.Saved, "https://docs.example/", "Docs"),
            ("Split Top", TabPlacement.Saved, "https://top.example/", "Docs"),
            ("Split Bottom", TabPlacement.Saved, "https://bottom.example/", "Docs"),
            ("Open One", TabPlacement.Current, "https://open-one.example/", null),
            ("Open Two", TabPlacement.Current, "https://open-two.example/", null)
        ], TabsOf(space));
        Assert.Equal([("Docs", null)], FoldersOf(space));
        Assert.Equal([["Split Left", "Split Right"], ["Split Top", "Split Bottom"], ["Open One", "Open Two"]], SplitsOf(space));
    }

    [Fact]
    public void ZenSpacesWearTheirIconAndTheColorsZenWrites() {
        // Zen spells a theme color as `c`, red, green and blue from 0 to 255,
        // and an icon as the path of one of its own, or an emoji.
        using var folder = new BrowserDataFolder();
        string session = Path.Combine(folder.Path, "zen-sessions.jsonlz4");
        File.WriteAllBytes(session, MozillaLz4("""
            {"spaces":[
              {"uuid":"a","name":"Trips","icon":"chrome://browser/skin/zen-icons/selectable/airplane.svg",
               "theme":{"gradientColors":[{"c":[232,121,64],"isPrimary":true},{"c":[64,175,232]}],"opacity":0.5}},
              {"uuid":"b","name":"Home","icon":"🏠"}],
             "tabs":[
              {"entries":[{"url":"https://trips.example/","title":"Trips"}],"zenWorkspace":"a"},
              {"entries":[{"url":"https://home.example/","title":"Home"}],"zenWorkspace":"b"}]}
            """));
        using var app = Importer();

        var spaces = app.Query(new ReadImport(ImportSource.Zen, [new("profile", "Zen", null, session)])).Spaces;
        Assert.Equal(("airplane", SpaceAccent.Orange, 2), (spaces[0].Settings.Symbol, spaces[0].Settings.Accent,
            spaces[0].Settings.Branding!.Colors.Colors.Count));
        Assert.Equal(EmojiIcon.Chosen("🏠")?.Symbol, spaces[1].Settings.Symbol);
    }

    [Fact]
    public void ArcSplitViewsComeAsSplitsAndItsTimesCountFrom2001() {
        // Arc keeps a split view as an item holding its tabs, and saves times
        // as seconds since 2001, as apps on Apple's platforms do.
        using var folder = new BrowserDataFolder();
        string sidebar = folder.Write("StorableSidebar.json", """
            {"sidebar":{"containers":[{
              "items":[
                "root",{"id":"root","childrenIds":["split","solo"],"data":{"itemContainer":{}}},
                "split",{"id":"split","childrenIds":["left","right"],"data":{"splitView":{"layoutOrientation":"horizontal"}}},
                "left",{"id":"left","data":{"tab":{"savedTitle":"Left","savedURL":"https://left.example/","timeLastActiveAt":812486952}}},
                "right",{"id":"right","data":{"tab":{"savedTitle":"Right","savedURL":"https://right.example/","timeLastActiveAt":812486952}}},
                "solo",{"id":"solo","data":{"tab":{"savedTitle":"Solo","savedURL":"https://solo.example/","timeLastActiveAt":812486952}}}],
              "spaces":["space",{"id":"space","title":"Arc Work","containerIDs":["pinned","root"]}]}]}}
            """);
        using var app = Importer();

        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Arc, [new("arc", "Arc", null, sidebar)])).Spaces);
        Assert.Equal([["Left", "Right"]], SplitsOf(space));
        Assert.All(space.Tabs, tab => Assert.Equal(2026, tab.LastActivatedAt.Year));
    }

    [Fact]
    public void SafarisPinnedTabsComeFromWhereItKeepsThemForEveryWindow() {
        var windows = Assert.Single(ReadSession("safari", "safari-pinned", "LastSession.plist"));

        Assert.Equal(("iCloud Mail", TabPlacement.Pinned), (windows.Tabs[0].Title, windows.Tabs[0].Placement));
        Assert.Equal(1, windows.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
    }

    [Fact]
    public void ChromiumTabGroupsBecomeFoldersOfOpenTabsAndItsSplitsSplits() {
        // A group becomes a folder among the open tabs in its color; a split of
        // pinned tabs, which no split holds, and one of a single tab show alone.
        var space = ReadGrouped(ImportSource.Chrome, GroupedCommands());

        var research = Assert.Single(space.Folders);
        Assert.Equal(("Research", TabPlacement.Current, TabGroupColor.Blue.Color), (research.Title, research.Location, research.Color));
        Assert.Equal(["Grouped A", "Grouped B"], space.Tabs.Where(tab => tab.FolderId == research.Id).Select(tab => tab.Title));
        Assert.Equal([["Split L", "Split R"]], SplitsOf(space));
    }

    [Fact]
    public void FirefoxTabGroupsBecomeFoldersOfOpenTabs() {
        // Firefox spells grey `gray`; a pinned tab stays out of any group.
        using var folder = new BrowserDataFolder();
        string session = Path.Combine(folder.Path, "sessionstore.jsonlz4");
        File.WriteAllBytes(session, MozillaLz4("""
            {"windows":[{"groups":[{"id":"g","name":"Research","color":"gray"}],"tabs":[
              {"entries":[{"url":"https://pinned.example/","title":"Pinned"}],"pinned":true,"groupId":"g"},
              {"entries":[{"url":"https://one.example/","title":"One"}],"groupId":"g"},
              {"entries":[{"url":"https://two.example/","title":"Two"}],"groupId":"g"},
              {"entries":[{"url":"https://alone.example/","title":"Alone"}]}]}],"selectedWindow":1}
            """));
        using var app = Importer();

        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Firefox, [new("profile", "Firefox", null, session)])).Spaces);
        var research = Assert.Single(space.Folders);
        Assert.Equal(("Research", TabPlacement.Current, TabGroupColor.Grey.Color), (research.Title, research.Location, research.Color));
        Assert.Equal(["One", "Two"], space.Tabs.Where(tab => tab.FolderId == research.Id).Select(tab => tab.Title));
    }

    [Fact]
    public void VivaldiNumbersChromiumsCommandsPastItsOwn() {
        // Vivaldi keeps records of its own at 21 and 22 and moves Chromium's
        // from 21 on two places up.
        List<(byte, byte[])> vivaldi = [(21, [1, 2, 3, 4]), (22, [5, 6, 7, 8])];
        vivaldi.AddRange(GroupedCommands().Select(command => (command.Id >= 21 && command.Id < 252 ? (byte)(command.Id + 2) : command.Id, command.Payload)));
        var space = ReadGrouped(ImportSource.Vivaldi, vivaldi);

        Assert.Equal("Research", Assert.Single(space.Folders).Title);
        Assert.Equal([["Split L", "Split R"]], SplitsOf(space));
    }

    /// The one Space `source` reads from a session file of `commands`.
    private static SpaceState ReadGrouped(ImportSource source, IEnumerable<(byte Id, byte[] Payload)> commands) {
        using var folder = new BrowserDataFolder();
        string session = Path.Combine(folder.Path, "Session_1");
        File.WriteAllBytes(session, Snss(commands));
        using var app = Importer();
        return Assert.Single(app.Query(new ReadImport(source, [new("Default", "Personal", null, session)])).Spaces);
    }

    /// A window of seven tabs: two in the blue group "Research", two open tabs
    /// in a split, two pinned tabs in a split, and one alone in a split.
    private static List<(byte Id, byte[] Payload)> GroupedCommands() {
        byte[] Tab(int id) => [.. BitConverter.GetBytes(1), .. BitConverter.GetBytes(id)];
        byte[] Token(int tab, ulong token) => [.. BitConverter.GetBytes(tab), 0, 0, 0, 0, .. BitConverter.GetBytes(token),
            .. BitConverter.GetBytes(token), 1, 0, 0, 0, 0, 0, 0, 0];
        List<(byte, byte[])> commands = [];
        string[] titles = ["Grouped A", "Grouped B", "Split L", "Split R", "Pinned L", "Pinned R", "Alone"];
        for (int id = 1; id <= titles.Length; id++) {
            commands.Add((0, Tab(id)));
            commands.Add((2, [.. BitConverter.GetBytes(id), .. BitConverter.GetBytes(id)]));
            commands.Add((6, Pickle(id, 0, $"https://tab{id}.example/", (titles[id - 1], true), "", 0)));
        }
        commands.AddRange([(25, Token(1, 7)), (25, Token(2, 7)), (27, Pickle(7UL, 7UL, ("Research", true), 1, 0, 0)),
            (36, Token(3, 8)), (36, Token(4, 8)), (12, [.. BitConverter.GetBytes(5), 1, 0, 0, 0]), (12, [.. BitConverter.GetBytes(6), 1, 0, 0, 0]),
            (36, Token(5, 9)), (36, Token(6, 9)), (36, Token(7, 10)), (255, [])]);
        return commands;
    }

    /// A Chromium session file of `commands`, each its identity and payload.
    private static byte[] Snss(IEnumerable<(byte Id, byte[] Payload)> commands) {
        List<byte> file = [.. "SNSS"u8, 3, 0, 0, 0];
        foreach (var (id, payload) in commands) file.AddRange([.. BitConverter.GetBytes((ushort)(payload.Length + 1)), id, .. payload]);
        return [.. file];
    }

    /// A Chromium pickle of `values`: 32-bit and 64-bit numbers, UTF-8 text,
    /// and UTF-16 text given with `true`, each padded to four bytes.
    private static byte[] Pickle(params object[] values) {
        List<byte> body = [];
        void Pad() { while (body.Count % 4 != 0) body.Add(0); }
        foreach (var value in values) {
            switch (value) {
                case int number: body.AddRange(BitConverter.GetBytes(number)); break;
                case ulong number: body.AddRange(BitConverter.GetBytes(number)); break;
                case string text: body.AddRange(BitConverter.GetBytes(Encoding.UTF8.GetByteCount(text))); body.AddRange(Encoding.UTF8.GetBytes(text)); Pad(); break;
                case (string text, true): body.AddRange(BitConverter.GetBytes(text.Length)); body.AddRange(Encoding.Unicode.GetBytes(text)); Pad(); break;
            }
        }
        return [.. BitConverter.GetBytes(body.Count), .. body];
    }

    /// `json` as Mozilla's LZ4 file, one block of literals.
    private static byte[] MozillaLz4(string json) {
        byte[] raw = Encoding.UTF8.GetBytes(json);
        List<byte> block = [(byte)(Math.Min(raw.Length, 15) << 4)];
        if (raw.Length >= 15) {
            int rest = raw.Length - 15;
            for (; rest >= 255; rest -= 255) block.Add(255);
            block.Add((byte)rest);
        }
        return [.. "mozLz40\0"u8, .. BitConverter.GetBytes(raw.Length), .. block, .. raw];
    }

    /// The titles of each split's tabs, split by split.
    private static string[][] SplitsOf(SpaceState space) =>
        [.. space.SplitGroups.Select(split => space.Tabs.Where(tab => tab.SplitGroupId == split.Id).Select(tab => tab.Title).ToArray())];

    [Fact]
    public void PinnedTabsPastWhatCrestPinsAreSavedInAFolderOfTheirOwn() {
        var space = Assert.Single(ReadSession("zen", "zen-overflow", Path.Combine("profile", "zen-sessions.jsonlz4")));

        Assert.Equal(TabPlacement.PinnedCapacity, space.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        var overflow = Assert.Single(space.Folders);
        Assert.Equal(("Imported Pinned Tabs", "pin.slash", TabPlacement.Saved), (overflow.Title, overflow.Symbol, overflow.Location));
        Assert.Equal(["Pin 13", "Pin 14"], space.Tabs.Where(tab => tab.FolderId == overflow.Id).Select(tab => tab.Title));
    }

    [Fact]
    public void AnOperaSessionReadsAsChromesDoesBesideItsOwnRecords() {
        // Opera writes records of its own under Chromium's initial-state marker,
        // 255, and marks the initial state with an empty 252 instead.
        byte[] chrome = File.ReadAllBytes(ImportFixture("chromium-windows", Path.Combine("Sessions", "Session_1")));
        List<byte> opera = [.. chrome[..8], 3, 0, 255, 1, 2];
        for (int position = 8; position < chrome.Length;) {
            int size = BitConverter.ToUInt16(chrome, position);
            if (chrome[position + 2] == 255 && size == 1) opera.AddRange([1, 0, 252]);
            else opera.AddRange(chrome[position..(position + 2 + size)]);
            position += 2 + size;
        }
        using var folder = new BrowserDataFolder();
        string session = Path.Combine(folder.Path, "Session_1");
        File.WriteAllBytes(session, [.. opera]);
        using var app = Importer();

        var space = Assert.Single(app.Query(new ReadImport(ImportSource.Opera, [new("profile", "Profile", null, session)])).Spaces);
        Assert.Equal(TabsOf(Assert.Single(ReadSession("chrome", "chromium-windows", Path.Combine("Sessions", "Session_1")))), TabsOf(space));
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

    [Fact]
    public void ASourceBringsTheSpacesThatFitAndLeavesOutTheRestWithWhy() {
        using var app = Importer();
        // Zen holds one Space more than a workspace keeps, none of them with
        // a tab: each comes, with its name and a start page, until the
        // workspace is full.
        var zen = app.Query(new ReadImport(ImportSource.Zen, [
            new("profile", "Zen", null, ImportFixture("zen-too-many-spaces", Path.Combine("profile", "zen-sessions.jsonlz4")))
        ]));
        Assert.Equal(BrowserDataFile.MaximumSpaces, zen.Spaces.Count);
        Assert.All(zen.Spaces, space => Assert.All(space.Tabs, tab => Assert.Null(tab.Url)));
        Assert.Equal([new ImportLeftOut("Space 64", new SessionOverLimits())], zen.LeftOut);

        // An Arc Space holding more tabs than a Space keeps is left out; one
        // holding as many folders as a Space keeps comes, as does the rest.
        JsonArray items = [];
        void Item(string id, JsonObject data, params string[] children) {
            items.Add((JsonNode)id);
            items.Add((JsonNode)new JsonObject {
                ["id"] = id,
                ["title"] = id,
                ["data"] = data,
                ["childrenIds"] = new JsonArray([.. children.Select(child => (JsonNode)child)])
            });
        }
        JsonObject Tab(string id) => new() { ["tab"] = new JsonObject { ["savedTitle"] = id, ["savedURL"] = $"https://{id}.example/" } };
        var many = Enumerable.Range(0, SessionDraft.MaximumTabs + 1).Select(index => $"t{index}").ToArray();
        var folders = Enumerable.Range(0, FolderTree.MaximumCount).Select(index => $"f{index}").ToArray();
        foreach (string id in many) Item(id, Tab(id));
        foreach (string id in folders) Item(id, new JsonObject { ["list"] = new JsonObject() });
        Item("small", Tab("small"));
        Item("big", [], many);
        Item("kept", [], folders);
        JsonObject Space(string title, params string[] sections) =>
            new() { ["id"] = title, ["title"] = title, ["containerIDs"] = new JsonArray([.. sections.Select(section => (JsonNode)section)]) };
        var container = new JsonObject {
            ["items"] = items,
            ["spaces"] = new JsonArray(Space("Big", "unpinned", "big"), Space("Folders", "pinned", "kept"), Space("Small", "unpinned", "small"))
        };
        using var folder = new BrowserDataFolder();
        string sidebar = folder.Write("StorableSidebar.json",
            new JsonObject { ["sidebar"] = new JsonObject { ["containers"] = new JsonArray(container) } }.ToJsonString());
        var arc = app.Query(new ReadImport(ImportSource.Arc, [new("arc", "Arc", null, sidebar)]));
        Assert.Equal(["Folders", "Small"], arc.Spaces.Select(space => space.Settings.Name));
        Assert.Equal(FolderTree.MaximumCount, arc.Spaces[0].Folders.Count);
        Assert.Equal([new ImportLeftOut("Big", new SessionOverLimits())], arc.LeftOut);
    }

    [Theory]
    [InlineData("arc", "sanitize-arc", "StorableSidebar.json", "https://arc.example/path#fragment")]
    [InlineData("zen", "sanitize-zen", "profile/zen-sessions.jsonlz4", "https://zen.example/path#fragment")]
    [InlineData("chrome", "sanitize-chrome", "Sessions/Session_1", "https://chromium.example/path#fragment")]
    [InlineData("firefox", "sanitize-firefox", "profile/recovery.jsonlz4", "https://firefox.example/path#fragment")]
    [InlineData("safari", "sanitize-safari", "LastSession.plist", "https://safari.example/path#fragment")]
    public void EveryBrowsersTabIsCleanedTheSameWay(string source, string name, string file, string url) {
        // Each file spells its title with extra white space and its address
        // with credentials and an uppercase scheme.
        var tab = Assert.Single(Assert.Single(ReadSession(source, name, file)).Tabs);

        Assert.Equal(("Shared Title", TabPlacement.Current, url), (tab.Title, tab.Placement, tab.Url));
    }

    [Theory]
    [InlineData("chrome", "chromium-encrypted", "Sessions/Session_3", typeof(SessionEncrypted))]
    [InlineData("chrome", "chromium-truncated", "Sessions/Session_4", typeof(SessionUnrecognized))]
    [InlineData("chrome", "chromium-malformed", "Sessions/Session_5", typeof(SessionUnrecognized))]
    [InlineData("chrome", "chromium-unmarked", "Sessions/Session_6", typeof(SessionUnrecognized))]
    [InlineData("firefox", "firefox-bad-block", "profile/recovery.jsonlz4", typeof(SessionUnrecognized))]
    [InlineData("firefox", "firefox-oversized", "profile/recovery.jsonlz4", typeof(SessionOverLimits))]
    [InlineData("safari", "safari-garbage", "LastSession.plist", typeof(SessionUnrecognized))]
    [InlineData("arc", "arc-garbage", "StorableSidebar.json", typeof(SessionUnrecognized))]
    [InlineData("zen", "zen-empty", "profile/zen-sessions.jsonlz4", typeof(SessionUnrecognized))]
    [InlineData("safari", "safari-windows", "Missing.plist", typeof(SessionUnrecognized))]
    public void ASessionCrestCannotReadIsRefusedWithWhatIsWrong(string source, string name, string file, Type refusal) =>
        Assert.IsType(refusal, Assert.Throws<Rejected>(() => ReadSession(source, name, file)).Rejection);
}
