namespace CrestCore.Contracts;

/// A tab the Getting Started practice starts with: the site it stands for,
/// the title it shows, the section it sits in and the icon it wears, which
/// the platforms bundle since its page never loads. `All` is the order the
/// practice Space holds them in.
public sealed class PracticeTab {
    #region Static Variables

    public static readonly PracticeTab Calendar = new(name: "calendar", title: "Calendar", url: "https://calendar.google.com",
        placement: TabPlacement.Pinned, artwork: "GuideCalendar");
    public static readonly PracticeTab Reading = new(name: "reading", title: "Wikipedia", url: "https://wikipedia.org",
        placement: TabPlacement.Saved, artwork: "GuideWikipedia");
    public static readonly PracticeTab Mail = new(name: "mail", title: "Gmail", url: "https://mail.google.com",
        placement: TabPlacement.Current, artwork: "GuideGmail");
    public static readonly PracticeTab Trail = new(name: "trail", title: "A weekend away", url: "https://www.alltrails.com",
        placement: TabPlacement.Current, artwork: "GuideAllTrails");
    public static readonly PracticeTab Packing = new(name: "packing", title: "Packing list", url: "https://todoist.com",
        placement: TabPlacement.Current, artwork: "GuideTodoist");

    public static IReadOnlyList<PracticeTab> All { get; } = [Calendar, Reading, Mail, Trail, Packing];

    #endregion

    #region Variables

    public string Name { get; }

    /// The title the tab shows.
    public string Title { get; }

    /// The address of the site the tab stands for.
    public string Url { get; }

    /// The section the tab starts in.
    public TabPlacement Placement { get; }

    /// The name of the icon the platforms bundle for the tab, which it wears
    /// since its page never loads.
    public string Artwork { get; }

    #endregion

    #region Constructors

    private PracticeTab(string name, string title, string url, TabPlacement placement, string artwork) {
        Name = name;
        Title = title;
        Url = url;
        Placement = placement;
        Artwork = artwork;
    }

    #endregion

    #region Actions - Lookup

    public static PracticeTab? Named(string? name) => All.FirstOrDefault(tab => tab.Name == name);

    #endregion

    #region Actions - Tabs

    /// The tab as the practice Space holds it, `id`, last used at `now`.
    public TabState Opened(Guid id, DateTimeOffset now) =>
        new(id, Title, Url, NativeContent: null, SavedUrl: null, TabIconMode.WebSymbol, FaviconUrl: null, IconAccent: null,
            StoredIconMode: null, Placement, FolderId: null, SplitGroupId: null, now, PositionModifiedAt: null, CustomTitle: null,
            TitleModifiedAt: null, KeepsPageLoaded: false);

    #endregion
}
