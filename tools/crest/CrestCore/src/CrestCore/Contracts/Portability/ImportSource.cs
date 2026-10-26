using CrestCore.Application;

namespace CrestCore.Contracts;

/// A browser whose data Crest imports: what the person sees about it, where
/// it keeps its data and how the Spaces it brings are named. On the Mac, the
/// platform finds the installed browser by `BundleIdentifier` and its data
/// under the person's home folder at `DataFolder`, and remembers a folder the
/// person granted access to under the source's `Name`, which therefore never
/// changes.
///
/// A source that names its own Spaces, as Arc and Zen do, brings them as they
/// are named there, falling back to `SpaceName`, or to `NumberedSpaceName`
/// when it brings several. Any other source brings one Space for each of its
/// profiles, named after the profile.
///
/// A source travels as its index in `All`, so `All` is append-only.
///
/// The browsers built on Chromium keep Chrome's layout, each in its own
/// folder and Keychain item. `OtherChromium` stands for one such browser Crest
/// does not list, which setup finds by looking: the platform names and shows
/// it as that browser, and reads it where the core found its data. Its
/// passwords stay where they are, since no Keychain item is known for it.
public sealed class ImportSource {
    #region Static Variables

    /// Where a Mac keeps applications' data, relative to the person's home folder.
    private const string ApplicationSupport = "Library/Application Support";

    public static readonly ImportSource Arc = new(name: "arc", title: "Arc", bundleIdentifier: "company.thebrowser.Browser",
        dataFolder: "Library/Application Support/Arc", description: "Spaces, tabs, folders, colors, icons, and passwords",
        symbol: "sidebar.left", accent: SpaceAccent.Indigo, spaceHeaderStyle: ImportSpaceHeaderStyle.SectionLabel,
        safeStorageService: "Arc Safe Storage", pinnedSectionTitle: "FAVORITES", listsNewTab: true, spaceName: "Imported Arc Tabs",
        numberedSpaceName: "Imported Arc Space %lld");
    public static readonly ImportSource Zen = new(name: "zen", title: "Zen", bundleIdentifier: "app.zen-browser.zen",
        dataFolder: "Library/Application Support/zen/Profiles",
        description: "Spaces, Essentials, pinned tabs, folders, open tabs, and colors", symbol: "circle.hexagongrid.fill",
        accent: SpaceAccent.Indigo, spaceHeaderStyle: ImportSpaceHeaderStyle.Identity, pinnedSectionTitle: "ESSENTIALS",
        spaceName: "Imported Zen Tabs", numberedSpaceName: "Imported Zen Space %lld");
    public static readonly ImportSource Chrome = new(name: "chrome", title: "Chrome", bundleIdentifier: "com.google.Chrome",
        dataFolder: "Library/Application Support/Google/Chrome", description: "Profiles, bookmarks, open tabs, and passwords",
        symbol: "globe", accent: SpaceAccent.Orange, spaceHeaderStyle: ImportSpaceHeaderStyle.Identity,
        safeStorageService: "Chrome Safe Storage", savedSectionTitle: "BOOKMARKS");
    public static readonly ImportSource Safari = new(name: "safari", title: "Safari", bundleIdentifier: "com.apple.Safari",
        dataFolder: "Library/Safari", description: "Bookmarks, windows, and open tabs", symbol: "safari", accent: SpaceAccent.Teal,
        spaceHeaderStyle: ImportSpaceHeaderStyle.Identity, savedSectionTitle: "BOOKMARKS");
    public static readonly ImportSource Firefox = new(name: "firefox", title: "Firefox", bundleIdentifier: "org.mozilla.firefox",
        dataFolder: "Library/Application Support/Firefox/Profiles", description: "Windows, open tabs, and pinned tabs",
        symbol: "flame", accent: SpaceAccent.Rose, spaceHeaderStyle: ImportSpaceHeaderStyle.Identity);
    public static readonly ImportSource ChromeBeta = ChromiumFamily(name: "chromeBeta", title: "Chrome Beta",
        bundleIdentifier: "com.google.Chrome.beta", dataFolder: "Google/Chrome Beta", safeStorageService: "Chrome Safe Storage",
        symbol: "globe", accent: SpaceAccent.Orange);
    public static readonly ImportSource ChromeDev = ChromiumFamily(name: "chromeDev", title: "Chrome Dev", bundleIdentifier: "com.google.Chrome.dev",
        dataFolder: "Google/Chrome Dev", safeStorageService: "Chrome Safe Storage", symbol: "globe", accent: SpaceAccent.Orange);
    public static readonly ImportSource ChromeCanary = ChromiumFamily(name: "chromeCanary", title: "Chrome Canary",
        bundleIdentifier: "com.google.Chrome.canary", dataFolder: "Google/Chrome Canary", safeStorageService: "Chrome Safe Storage",
        symbol: "bird", accent: SpaceAccent.Orange);
    public static readonly ImportSource Chromium = ChromiumFamily(name: "chromium", title: "Chromium", bundleIdentifier: "org.chromium.Chromium",
        dataFolder: "Chromium", safeStorageService: "Chromium Safe Storage", symbol: "circle.circle", accent: SpaceAccent.Teal);
    public static readonly ImportSource Brave = ChromiumFamily(name: "brave", title: "Brave", bundleIdentifier: "com.brave.Browser",
        dataFolder: "BraveSoftware/Brave-Browser", safeStorageService: "Brave Safe Storage", symbol: "shield.lefthalf.filled",
        accent: SpaceAccent.Orange);
    public static readonly ImportSource Edge = ChromiumFamily(name: "edge", title: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac",
        dataFolder: "Microsoft Edge", safeStorageService: "Microsoft Edge Safe Storage", symbol: "water.waves", accent: SpaceAccent.Teal);
    public static readonly ImportSource Vivaldi = ChromiumFamily(name: "vivaldi", title: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi",
        dataFolder: "Vivaldi", safeStorageService: "Vivaldi Safe Storage", symbol: "v.circle.fill", accent: SpaceAccent.Rose);
    public static readonly ImportSource Opera = ChromiumFamily(name: "opera", title: "Opera", bundleIdentifier: "com.operasoftware.Opera",
        dataFolder: "com.operasoftware.Opera", safeStorageService: "Opera Safe Storage", symbol: "o.circle", accent: SpaceAccent.Rose);
    public static readonly ImportSource Dia = ChromiumFamily(name: "dia", title: "Dia", bundleIdentifier: "company.thebrowser.dia",
        dataFolder: "Dia/User Data", safeStorageService: "Dia Safe Storage", symbol: "sparkles", accent: SpaceAccent.Indigo);
    public static readonly ImportSource Comet = ChromiumFamily(name: "comet", title: "Comet", bundleIdentifier: "ai.perplexity.comet",
        dataFolder: "Comet", safeStorageService: "Comet Safe Storage", symbol: "sparkle.magnifyingglass", accent: SpaceAccent.Teal);
    public static readonly ImportSource Aside = ChromiumFamily(name: "aside", title: "Aside", bundleIdentifier: "at.studio.AsideBrowser",
        dataFolder: "Aside", safeStorageService: "Aside Safe Storage", symbol: "sidebar.right", accent: SpaceAccent.Indigo);
    public static readonly ImportSource EgoLite = ChromiumFamily(name: "egoLite", title: "ego lite", bundleIdentifier: "com.citrolabs.ego.lite",
        dataFolder: "Citro Labs/ego lite", safeStorageService: "Chromium Safe Storage", symbol: "e.circle", accent: SpaceAccent.Indigo);
    public static readonly ImportSource OtherChromium = new(name: "otherChromium", title: "Chromium-based browser", bundleIdentifier: "",
        dataFolder: ApplicationSupport, description: "Profiles, bookmarks, and open tabs", symbol: "globe", accent: SpaceAccent.Teal,
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

    public SpaceAccent Accent { get; }

    /// The Keychain item where the Mac keeps the key the browser encrypts its
    /// saved passwords with, or null for a browser whose passwords Crest does
    /// not import.
    public string? SafeStorageService { get; }

    /// The browser keeps passwords Crest can import beside its tabs.
    public bool SuppliesPasswords => SafeStorageService is not null;

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
        SpaceAccent accent, ImportSpaceHeaderStyle spaceHeaderStyle, string? safeStorageService = null,
        string pinnedSectionTitle = "PINNED", string savedSectionTitle = "SAVED", bool listsNewTab = false, string? spaceName = null,
        string? numberedSpaceName = null, bool isListed = true) {
        Name = name;
        Title = title;
        BundleIdentifier = bundleIdentifier;
        DataFolder = dataFolder;
        Description = description;
        Symbol = symbol;
        Accent = accent;
        SafeStorageService = safeStorageService;
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

    #region Actions - Passwords

    /// How many of `passwords` belong with each of `spaces`, by Space. A
    /// browser whose Spaces are its profiles gives a password to its own
    /// profile's Space and to no other; one that names its own Spaces gives it
    /// to every Space holding its site, or a site one of them is a subdomain
    /// of. A browser that keeps no passwords routes none.
    internal IReadOnlyDictionary<Guid, int> PasswordCounts(IReadOnlyList<ImportPasswordSource> passwords, IReadOnlyList<SpaceState> spaces) {
        ArgumentNullException.ThrowIfNull(passwords);
        var sites = SpaceSites.Of(spaces);
        var counts = new Dictionary<Guid, int>();
        foreach (var password in passwords)
            foreach (var spaceId in SpacesFor(password, spaces, sites))
                counts[spaceId] = counts.GetValueOrDefault(spaceId) + 1;
        return counts;
    }

    /// The Spaces among `spaces` that `password` belongs with.
    internal IEnumerable<Guid> SpacesFor(ImportPasswordSource password, IReadOnlyList<SpaceState> spaces,
        IReadOnlyDictionary<Guid, SpaceSites> sites) {
        if (!SuppliesPasswords) return [];
        if (NamesItsSpaces) return spaces.Where(space => sites[space.Id].Holds(password.Host)).Select(space => space.Id);
        var profile = spaces.FirstOrDefault(space => string.Equals(space.Settings.Name, password.ProfileName, StringComparison.Ordinal));
        return profile is null ? [] : [profile.Id];
    }

    #endregion

    #region Actions - Construction

    /// A browser built on Chromium that keeps Chrome's layout in `dataFolder`
    /// below Application Support, and the key to its passwords in the
    /// Keychain item `safeStorageService`.
    private static ImportSource ChromiumFamily(string name, string title, string bundleIdentifier, string dataFolder, string safeStorageService,
        string symbol, SpaceAccent accent) =>
        new(name: name, title: title, bundleIdentifier: bundleIdentifier, dataFolder: $"{ApplicationSupport}/{dataFolder}",
            description: "Profiles, bookmarks, open tabs, and passwords", symbol: symbol, accent: accent,
            spaceHeaderStyle: ImportSpaceHeaderStyle.Identity, safeStorageService: safeStorageService, savedSectionTitle: "BOOKMARKS");

    #endregion
}
