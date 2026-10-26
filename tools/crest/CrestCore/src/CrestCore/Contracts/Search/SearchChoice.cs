namespace CrestCore.Contracts;

/// One value a search provider's menu option offers, by what a person reads
/// in the menu: a safe-search level, a kind of result, an order. Options share
/// the words, and each option says what its choices do to its own provider's
/// address. The device store keeps a person's choice as its `Name`, so a name
/// never changes. A choice travels as its index in `All`, so `All` is
/// append-only.
public sealed class SearchChoice {
    #region Static Variables

    public static readonly SearchChoice Moderate = new(name: "moderate", title: "Moderate");
    public static readonly SearchChoice Strict = new(name: "strict", title: "Strict");
    public static readonly SearchChoice Off = new(name: "off", title: "Off");
    public static readonly SearchChoice Everything = new(name: "everything", title: "All");
    public static readonly SearchChoice Videos = new(name: "videos", title: "Videos");
    public static readonly SearchChoice Shorts = new(name: "shorts", title: "Shorts");
    public static readonly SearchChoice Channels = new(name: "channels", title: "Channels");
    public static readonly SearchChoice Playlists = new(name: "playlists", title: "Playlists");
    public static readonly SearchChoice Repositories = new(name: "repositories", title: "Repositories");
    public static readonly SearchChoice Code = new(name: "code", title: "Code");
    public static readonly SearchChoice Issues = new(name: "issues", title: "Issues");
    public static readonly SearchChoice PullRequests = new(name: "pullRequests", title: "Pull Requests");
    public static readonly SearchChoice Discussions = new(name: "discussions", title: "Discussions");
    public static readonly SearchChoice Users = new(name: "users", title: "Users");
    public static readonly SearchChoice BestMatch = new(name: "bestMatch", title: "Best Match");
    public static readonly SearchChoice MostStars = new(name: "mostStars", title: "Most Stars");
    public static readonly SearchChoice RecentlyUpdated = new(name: "recentlyUpdated", title: "Recently Updated");
    public static readonly SearchChoice Relevance = new(name: "relevance", title: "Relevance");
    public static readonly SearchChoice Newest = new(name: "newest", title: "Newest");
    public static readonly SearchChoice MostVotes = new(name: "mostVotes", title: "Most Votes");
    public static readonly SearchChoice Titles = new(name: "titles", title: "Titles");
    public static readonly SearchChoice People = new(name: "people", title: "People");
    public static readonly SearchChoice Companies = new(name: "companies", title: "Companies");
    public static readonly SearchChoice Keywords = new(name: "keywords", title: "Keywords");
    public static readonly SearchChoice Songs = new(name: "songs", title: "Songs");
    public static readonly SearchChoice Artists = new(name: "artists", title: "Artists");
    public static readonly SearchChoice Albums = new(name: "albums", title: "Albums");
    public static readonly SearchChoice Podcasts = new(name: "podcasts", title: "Podcasts & Shows");
    public static readonly SearchChoice Explore = new(name: "explore", title: "Explore");
    public static readonly SearchChoice Satellite = new(name: "satellite", title: "Satellite");
    public static readonly SearchChoice Hybrid = new(name: "hybrid", title: "Hybrid");
    public static readonly SearchChoice Transit = new(name: "transit", title: "Transit");
    public static readonly SearchChoice Popular = new(name: "popular", title: "Popular");
    public static readonly SearchChoice Stories = new(name: "stories", title: "Stories");
    public static readonly SearchChoice Comments = new(name: "comments", title: "Comments");

    /// Every choice, in the order they were added.
    public static IReadOnlyList<SearchChoice> All { get; } = [Moderate, Strict, Off, Everything, Videos, Shorts, Channels, Playlists, Repositories,
        Code, Issues, PullRequests, Discussions, Users, BestMatch, MostStars, RecentlyUpdated, Relevance, Newest, MostVotes, Titles, People,
        Companies, Keywords, Songs, Artists, Albums, Podcasts, Explore, Satellite, Hybrid, Transit, Popular, Stories, Comments];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the option's menu says for the choice.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SearchChoice(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SearchChoice? Named(string? name) => All.FirstOrDefault(choice => choice.Name == name);

    #endregion
}
