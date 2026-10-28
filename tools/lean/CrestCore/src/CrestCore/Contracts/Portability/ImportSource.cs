using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed class ImportSource {
    #region Static Variables

    /// Where a Mac keeps applications' data, relative to the person's home folder.
    private const string ApplicationSupport = "Library/Application Support";

    public static readonly ImportSource Arc = new(name: "arc", title: "Arc", bundleIdentifier: "company.thebrowser.Browser",
        dataFolder: "Library/Application Support/Arc", description: "Spaces, tabs, and folders",
        symbol: "sidebar.left", spaceHeaderStyle: ImportSpaceHeaderStyle.SectionLabel,
        pinnedSectionTitle: "FAVORITES", listsNewTab: true, spaceName: "Imported Arc Tabs",
        numberedSpaceName: "Imported Arc Space %lld");
    public static readonly ImportSource Zen = new(name: "zen", title: "Zen", bundleIdentifier: "app.zen-browser.zen",
        dataFolder: "Library/Application Support/zen/Profiles",
        description: "Spaces, Essentials, pinned tabs, folders, open tabs, and colors", symbol: "circle.hexagongrid.fill", spaceHeaderStyle: ImportSpaceHeaderStyle.Identity, pinnedSectionTitle: "ESSENTIALS",
        spaceName: "Imported Zen Tabs", numberedSpaceName: "Imported Zen Space %lld");
    public static readonly ImportSource Chrome = new(name: "chrome", title: "Chrome", bundleIdentifier: "com.google.Chrome",
        dataFolder: "Library/Application Support/Google/Chrome", description: "Profiles, bookmarks, and open tabs",
        symbol: "globe", spaceHeaderStyle: ImportSpaceHeaderStyle.Identity,
        savedSectionTitle: "BOOKMARKS");
    public static readonly ImportSource Safari = new(name: "safari", title: "Safari", bundleIdentifier: "com.apple.Safari",
        dataFolder: "Library/Safari", description: "Bookmarks, windows, and open tabs", symbol: "safari",
        spaceHeaderStyle: ImportSpaceHeaderStyle.Identity, savedSectionTitle: "BOOKMARKS");
    public static readonly ImportSource Firefox = new(name: "firefox", title: "Firefox", bundleIdentifier: "org.mozilla.firefox",
        dataFolder: "Library/Application Support/Firefox/Profiles", description: "Windows, open tabs, and pinned tabs",
        symbol: "flame", spaceHeaderStyle: ImportSpaceHeaderStyle.Identity);
    public static readonly ImportSource ChromeBeta = ChromiumFamily(name: "chromeBeta", title: "Chrome Beta",
        bundleIdentifier: "com.google.Chrome.beta", dataFolder: "Google/Chrome Beta", symbol: "globe");
    public static readonly ImportSource ChromeDev = ChromiumFamily(name: "chromeDev", title: "Chrome Dev", bundleIdentifier: "com.google.Chrome.dev",
        dataFolder: "Google/Chrome Dev", symbol: "globe");
    public static readonly ImportSource ChromeCanary = ChromiumFamily(name: "chromeCanary", title: "Chrome Canary",
        bundleIdentifier: "com.google.Chrome.canary", dataFolder: "Google/Chrome Canary", symbol: "bird");
    public static readonly ImportSource Chromium = ChromiumFamily(name: "chromium", title: "Chromium", bundleIdentifier: "org.chromium.Chromium",
        dataFolder: "Chromium", symbol: "circle.circle");
    public static readonly ImportSource Brave = ChromiumFamily(name: "brave", title: "Brave", bundleIdentifier: "com.brave.Browser",
        dataFolder: "BraveSoftware/Brave-Browser", symbol: "shield.lefthalf.filled");
    public static readonly ImportSource Edge = ChromiumFamily(name: "edge", title: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac",
        dataFolder: "Microsoft Edge", symbol: "water.waves");
    public static readonly ImportSource Vivaldi = ChromiumFamily(name: "vivaldi", title: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi",
        dataFolder: "Vivaldi", symbol: "v.circle.fill");
    public static readonly ImportSource Opera = ChromiumFamily(name: "opera", title: "Opera", bundleIdentifier: "com.operasoftware.Opera",
        dataFolder: "com.operasoftware.Opera", symbol: "o.circle");
    public static readonly ImportSource Dia = ChromiumFamily(name: "dia", title: "Dia", bundleIdentifier: "company.thebrowser.dia",
        dataFolder: "Dia/User Data", symbol: "sparkles");
    public static readonly ImportSource Comet = ChromiumFamily(name: "comet", title: "Comet", bundleIdentifier: "ai.perplexity.comet",
        dataFolder: "Comet", symbol: "sparkle.magnifyingglass");
    public static readonly ImportSource Aside = ChromiumFamily(name: "aside", title: "Aside", bundleIdentifier: "at.studio.AsideBrowser",
        dataFolder: "Aside", symbol: "sidebar.right");
    public static readonly ImportSource EgoLite = ChromiumFamily(name: "egoLite", title: "ego lite", bundleIdentifier: "com.citrolabs.ego.lite",
        dataFolder: "Citro Labs/ego lite", symbol: "e.circle");
    public static readonly ImportSource OtherChromium = new(name: "otherChromium", title: "Chromium-based browser", bundleIdentifier: "",
        dataFolder: ApplicationSupport, description: "Profiles, bookmarks, and open tabs", symbol: "globe",
        spaceHeaderStyle: ImportSpaceHeaderStyle.Identity, savedSectionTitle: "BOOKMARKS", isListed: false);

    public static IReadOnlyList<ImportSource> All { get; } = [Arc, Zen, Chrome, Safari, Firefox, ChromeBeta, ChromeDev, ChromeCanary,
        Chromium, Brave, Edge, Vivaldi, Opera, Dia, Comet, Aside, EgoLite, OtherChromium];

    #endregion

    #region Variables

    public string Name { get; }

    /// The browser's name, which is never translated.
    public string Title { get; }

    /// How the Mac finds the installed browser.
    public string BundleIdentifier { get; }

    /// Where the browser keeps its data on the Mac, relative to the person's
    /// home folder.
    public string DataFolder { get; }

    /// What an import from the browser brings, as the person reads it.
    [Localized]
    public string Description { get; }

    public string DescriptionComment { get; } = "What importing from another browser brings. Keep product names as they are.";

    /// The SF Symbol and accent the Spaces the browser brings wear unless it
    /// gives them its own.
    public string Symbol { get; }




    /// How a review names each Space the browser brings.
    public ImportSpaceHeaderStyle SpaceHeaderStyle { get; }

    /// What a review calls the pinned tabs and the saved ones, as the
    /// browser's own sidebar does.
    [Localized]
    public string PinnedSectionTitle { get; }

    public string PinnedSectionTitleComment { get; } = "A section heading in a browser import review. Keep it uppercase.";

    [Localized]
    public string SavedSectionTitle { get; }

    public string SavedSectionTitleComment { get; } = "A section heading in a browser import review. Keep it uppercase.";

    /// The browser lists a New Tab row where a Space shows no open tab, which
    /// a review shows as the browser would.
    public bool ListsNewTab { get; }

    /// What a Space the browser brings unnamed is called, or null when the
    /// browser's Spaces are named after its profiles.
    [Localized]
    public string? SpaceName { get; }

    /// What each of several Spaces the browser brings unnamed is called, its
    /// ordinal in place of `%lld`, or null when the browser's Spaces are named
    /// after its profiles.
    [Localized(IsFormat = true)]
    public string? NumberedSpaceName { get; }

    /// The source names its own Spaces, rather than bringing one Space for
    /// each of its profiles.
    public bool NamesItsSpaces => SpaceName is not null;

    /// Setup lists the browser by name and finds its data in a folder of its
    /// own; `OtherChromium` stands for any browser setup finds by looking.
    public bool IsListed { get; }

    #endregion

    #region Constructors

    private ImportSource(string name, string title, string bundleIdentifier, string dataFolder, string description, string symbol,
        ImportSpaceHeaderStyle spaceHeaderStyle,
        string pinnedSectionTitle = "PINNED", string savedSectionTitle = "SAVED", bool listsNewTab = false, string? spaceName = null,
        string? numberedSpaceName = null, bool isListed = true) {
        Name = name;
        Title = title;
        BundleIdentifier = bundleIdentifier;
        DataFolder = dataFolder;
        Description = description;
        Symbol = symbol;
        SpaceHeaderStyle = spaceHeaderStyle;
        PinnedSectionTitle = pinnedSectionTitle;
        SavedSectionTitle = savedSectionTitle;
        ListsNewTab = listsNewTab;
        SpaceName = spaceName;
        NumberedSpaceName = numberedSpaceName;
        IsListed = isListed;
    }

    #endregion

    #region Actions - Lookup

    public static ImportSource? Named(string? name) => All.FirstOrDefault(source => source.Name == name);

    #endregion



    #region Actions - Construction

    private static ImportSource ChromiumFamily(string name, string title, string bundleIdentifier, string dataFolder,
        string symbol) =>
        new(name: name, title: title, bundleIdentifier: bundleIdentifier, dataFolder: $"{ApplicationSupport}/{dataFolder}",
            description: "Profiles, bookmarks, and open tabs", symbol: symbol,
            spaceHeaderStyle: ImportSpaceHeaderStyle.Identity, savedSectionTitle: "BOOKMARKS");

    #endregion
}
