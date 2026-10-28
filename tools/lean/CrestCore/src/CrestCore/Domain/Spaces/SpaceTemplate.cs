using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed class SpaceTemplate {
    #region Static Variables

    /// A new Space keeps what it browses until the person chooses otherwise.
    private static readonly DataRetentionPreferences KeepsEverything = new(DataRetention.Forever, DataRetention.Forever,
        DataRetention.Forever);

    private static readonly BrowsingPreferences OrdinaryBrowsing = new(ContentBlockingPolicy.Balanced, KeepsEverything);

    public static readonly SpaceTemplate Ordinary = new(isPrivate: false, name: number => $"Space {number}",
        browsing: OrdinaryBrowsing, tabs: StartPage);

    public static readonly SpaceTemplate Private = new(isPrivate: true, name: number => number == 1 ? "Private" : $"Private {number}",
        browsing: OrdinaryBrowsing, tabs: StartPage);

    /// The templates a workspace's new Spaces come from, one for each privacy.
    public static IReadOnlyList<SpaceTemplate> All { get; } = [Ordinary, Private];

    /// The one Space a first launch starts with when nothing is carried to it:
    /// Personal, with one Start Page tab. No
    /// new Space comes from it.
    public static readonly SpaceTemplate FirstInstall = new(isPrivate: false, name: _ => "Personal",
        browsing: OrdinaryBrowsing,
        tabs: StartPage);

    #endregion

    #region Variables

    /// Whether this is the template of a private workspace's Spaces.
    public bool IsPrivate { get; }

    private readonly Func<int, string> name;
    private readonly BrowsingPreferences browsing;
    /// The tabs a new Space starts with, given a source of tab identities and
    /// the time it starts.
    private readonly Func<Func<Guid>, DateTimeOffset, IReadOnlyList<TabState>> tabs;

    #endregion

    #region Constructors

    private SpaceTemplate(bool isPrivate, Func<int, string> name,
        BrowsingPreferences browsing,
        Func<Func<Guid>, DateTimeOffset, IReadOnlyList<TabState>> tabs) {
        IsPrivate = isPrivate;
        this.name = name;
        this.browsing = browsing;
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
        var settings = new SpaceSettings(name(number), browsing, StoredColor: SpaceColor.All[(number - 1) % SpaceColor.All.Count]);
        return new(spaceId, profileId, settings, Folders: [], Tabs: tabs(tabIds, now), ArchivedTabs: [], History: []);
    }

    /// One Start Page tab, open.
    private static IReadOnlyList<TabState> StartPage(Func<Guid> tabIds, DateTimeOffset now) {
        var content = TabKind.StartPage;
        return [new TabState(tabIds(), content.Name, Url: null, NativeContent: null, SavedUrl: null, content.Symbol, FaviconUrl: null,
            IconAccent: null, StoredIconMode: null, TabPlacement.Current, FolderId: null, SplitGroupId: null, now,
            PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null)];
    }

    #endregion
}
