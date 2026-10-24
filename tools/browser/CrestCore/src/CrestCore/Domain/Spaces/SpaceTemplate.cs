using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a new Space starts as in each kind of workspace: its name, symbol,
/// accent and look, what it searches and keeps, whether it offers to save
/// passwords, and the tabs it starts with. Every new Space has a profile of
/// its own and opens freely. An ordinary Space takes the next accent in turn
/// and wears that accent's house look; a private one wears the private look
/// and never offers to save or sync passwords. Both start with one Start Page
/// tab. The Getting Started practice starts from its own Space, holding the
/// practice tabs, and a first launch from the Personal Space.
public sealed class SpaceTemplate {
    #region Static Variables

    /// A new Space keeps what it browses until the person chooses otherwise.
    private static readonly DataRetentionPreferences KeepsEverything = new(DataRetention.Forever, DataRetention.Forever,
        DataRetention.Forever);

    /// The one purple a private Space wears, with a plain key for its symbol.
    private static readonly SpaceBranding PrivateLook = new(new([new(0.58, 0.30, 0.76)]), SpaceBannerPattern.Solid,
        BannerStrength: 1, ReadabilityFade: 1, KeepsControlsReadable: true, SpaceThemeMode.Banner, GradientAngle: 0,
        ShowsTexture: false, SpaceIconStyle.SimpleSymbol, SymbolColor: null,
        SpaceCrest.PlainField(CrestBackplate.None, CrestSymbol.Key, CrestTrim.None, layers: [0, 0, 0, 0, 0, 0], trimWeight: 1,
            chargeScale: 1),
        RenderingVersion: 2, FolderColorIntensity: 0, SpaceTextColorMode.Automatic, HasCustomAppearance: null);

    /// What an ordinary Space searches and keeps: the device's default search
    /// and suggestions, which it follows.
    private static readonly BrowsingPreferences OrdinaryBrowsing = new(BuiltInSearchProvider.Google, SelectedCustomEngineId: null, [],
        SearchSuggestionsEnabled: false, FollowsDefaultSearch: true, FollowsDefaultSuggestions: true, CurrentTabCleanup.After12Hours,
        ContentBlockingPolicy.Balanced, KeepsEverything);

    /// A Space that offers to save passwords and sync Crest's with iCloud.
    private static readonly CredentialPreferences SavesPasswords = new(IsEnabled: true, SyncsCrestPasswordsWithICloud: true,
        AlsoOffersSaveToSystemPasswords: false);

    /// A Space that never offers to save or sync passwords.
    private static readonly CredentialPreferences NoPasswords = new(IsEnabled: false, SyncsCrestPasswordsWithICloud: false,
        AlsoOffersSaveToSystemPasswords: false);

    public static readonly SpaceTemplate Ordinary = new(isPrivate: false, name: number => $"Space {number}",
        symbol: "square.grid.2x2.fill", accent: number => SpaceAccent.All[(number - 1) % SpaceAccent.All.Count],
        look: accent => accent.House, browsing: OrdinaryBrowsing, credentials: SavesPasswords, tabs: StartPage);

    public static readonly SpaceTemplate Private = new(isPrivate: true, name: number => number == 1 ? "Private" : $"Private {number}",
        symbol: "eyeglasses", accent: _ => SpaceAccent.Indigo, look: _ => PrivateLook,
        browsing: new(BuiltInSearchProvider.DuckDuckGo, SelectedCustomEngineId: null, [], SearchSuggestionsEnabled: false,
            FollowsDefaultSearch: true, FollowsDefaultSuggestions: false, CurrentTabCleanup.Never, ContentBlockingPolicy.Balanced,
            KeepsEverything),
        credentials: NoPasswords, tabs: StartPage);

    /// The templates a workspace's new Spaces come from, one for each privacy.
    public static IReadOnlyList<SpaceTemplate> All { get; } = [Ordinary, Private];

    /// The one Space the Getting Started practice starts with, holding every
    /// practice tab in its order. It never offers to save passwords, and no
    /// new Space comes from it.
    public static readonly SpaceTemplate Practice = new(isPrivate: false, name: _ => "Practice", symbol: "leaf.fill",
        accent: _ => SpaceAccent.Indigo, look: accent => accent.House, browsing: OrdinaryBrowsing, credentials: NoPasswords,
        tabs: (tabIds, now) => [.. PracticeTab.All.Select(tab => tab.Opened(tabIds(), now))]);

    /// The one Space a first launch starts with when nothing is carried to it:
    /// Personal, wearing the Winter house look, with one Start Page tab. No
    /// new Space comes from it.
    public static readonly SpaceTemplate FirstInstall = new(isPrivate: false, name: _ => "Personal", symbol: "person.fill",
        accent: _ => SpaceAccent.Indigo, look: accent => accent.House, browsing: OrdinaryBrowsing, credentials: SavesPasswords,
        tabs: StartPage);

    #endregion

    #region Variables

    /// Whether this is the template of a private workspace's Spaces.
    public bool IsPrivate { get; }

    /// The symbol a new Space of this template wears.
    public string Symbol => symbol;

    private readonly Func<int, string> name;
    private readonly string symbol;
    private readonly Func<int, SpaceAccent> accent;
    private readonly Func<SpaceAccent, SpaceBranding> look;
    private readonly BrowsingPreferences browsing;
    private readonly CredentialPreferences credentials;
    /// The tabs a new Space starts with, given a source of tab identities and
    /// the time it starts.
    private readonly Func<Func<Guid>, DateTimeOffset, IReadOnlyList<TabState>> tabs;

    #endregion

    #region Constructors

    private SpaceTemplate(bool isPrivate, Func<int, string> name, string symbol, Func<int, SpaceAccent> accent,
        Func<SpaceAccent, SpaceBranding> look, BrowsingPreferences browsing, CredentialPreferences credentials,
        Func<Func<Guid>, DateTimeOffset, IReadOnlyList<TabState>> tabs) {
        IsPrivate = isPrivate;
        this.name = name;
        this.symbol = symbol;
        this.accent = accent;
        this.look = look;
        this.browsing = browsing;
        this.credentials = credentials;
        this.tabs = tabs;
    }

    #endregion

    #region Actions - Lookup

    /// The template of a private workspace's Spaces, or of an ordinary one's.
    public static SpaceTemplate For(bool privateBrowsing) => All.Single(template => template.IsPrivate == privateBrowsing);

    #endregion

    #region Actions - Spaces

    /// The Space that is `number`th in its workspace, counting from one, with
    /// `profileId` for its profile and the template's tabs, each taking its
    /// identity from `tabIds`, used at `now`.
    public SpaceState Make(Guid spaceId, Guid profileId, Func<Guid> tabIds, int number, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(tabIds);
        ArgumentOutOfRangeException.ThrowIfLessThan(number, 1);
        var shade = accent(number);
        var settings = new SpaceSettings(name(number), symbol, shade, look(shade), browsing, credentials, SpaceAccessPolicy.Open,
            IsSavedTabsExpanded: true, SavedTabsExpansionModifiedAt: null);
        return new(spaceId, profileId, settings, Folders: [], Tabs: tabs(tabIds, now), SplitGroups: [], ArchivedTabs: [], History: []);
    }

    /// One Start Page tab, open.
    private static IReadOnlyList<TabState> StartPage(Func<Guid> tabIds, DateTimeOffset now) {
        var content = TabKind.StartPage;
        return [new TabState(tabIds(), content.Name, Url: null, NativeContent: null, SavedUrl: null, content.Symbol, FaviconUrl: null,
            IconAccent: null, StoredIconMode: null, TabPlacement.Current, FolderId: null, SplitGroupId: null, now,
            PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null, KeepsPageLoaded: false)];
    }

    #endregion
}
