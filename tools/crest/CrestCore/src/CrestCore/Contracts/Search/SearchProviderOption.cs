using CrestCore.Domain;

namespace CrestCore.Contracts;

#region Types

/// One place a language, region or store option offers: `Code` is how the
/// provider's address spells it, `Locale` the locale identifier Settings names
/// it by, and `AlsoServes` the further regions it is the automatic choice for,
/// as Amazon's German store is in Austria.
public sealed record SearchLocaleCode(string Code, string Locale, IReadOnlyList<string> AlsoServes) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<string> AlsoServes {
        get;
        init => field = [.. value];
    } = [.. AlsoServes];

    #endregion

    #region Actions - Equality

    public bool Equals(SearchLocaleCode? other) =>
        other is not null && Code == other.Code && Locale == other.Locale && AlsoServes.SequenceEqual(other.AlsoServes);

    public override int GetHashCode() => HashCode.Combine(Code, Locale, AlsoServes.Count);

    #endregion
}

#endregion

/// A setting a built-in search provider offers, which changes the address it
/// searches. Each option is a switch, a menu of choices, a menu of languages,
/// regions or stores that starts as automatic, or text a person types, and
/// says what each value does to its provider's address. A blank value is the
/// option's default: a switch off, a menu's first choice, an automatic
/// language or region, or text that adds nothing. The device store keeps a
/// value by the option's `Name`, so a name never changes; an option travels as
/// its index in `All`, so `All` is append-only.
public sealed class SearchProviderOption {
    #region Static Variables

    /// The value a switch keeps while it is on.
    public const string On = "on";

    /// The longest text a person may type for an option.
    public const int MaximumTextLength = 128;

    public static readonly SearchProviderOption GoogleHidesAIOverviews = Switch("googleHidesAIOverviews", "Hide AI Overviews",
        new AddsParameter("udm", "14"));
    public static readonly SearchProviderOption GoogleSafeSearch = Switch("googleSafeSearch", "SafeSearch", new AddsParameter("safe", "active"));
    public static readonly SearchProviderOption GoogleExactWords = Switch("googleExactWords", "Exact Words", new AddsParameter("tbs", "li:1"));
    public static readonly SearchProviderOption DuckDuckGoHidesAI = Switch("duckDuckGoHidesAI", "Hide AI Features",
        new FillsSlot(SearchSlot.Host, "noai.duckduckgo.com"));
    public static readonly SearchProviderOption DuckDuckGoSafeSearch = Menu("duckDuckGoSafeSearch", "Safe Search",
        (SearchChoice.Moderate, []), (SearchChoice.Strict, [new AddsParameter("kp", "1")]), (SearchChoice.Off, [new AddsParameter("kp", "-2")]));
    public static readonly SearchProviderOption DuckDuckGoRegion = Places("duckDuckGoRegion", "Region", namesRegions: true, follows: null,
        code => new AddsParameter("kl", code), Codes(("us-en", "en-US"), ("uk-en", "en-GB"), ("ca-en", "en-CA"), ("au-en", "en-AU"),
            ("in-en", "en-IN"), ("de-de", "de-DE"), ("at-de", "de-AT"), ("ch-de", "de-CH"), ("fr-fr", "fr-FR"), ("es-es", "es-ES"),
            ("mx-es", "es-MX"), ("it-it", "it-IT"), ("nl-nl", "nl-NL"), ("se-sv", "sv-SE"), ("br-pt", "pt-BR"), ("jp-jp", "ja-JP")));
    public static readonly SearchProviderOption BingMarket = Places("bingMarket", "Market", namesRegions: false, follows: null,
        code => new AddsParameter("setmkt", code), Codes(("en-US", "en-US"), ("en-GB", "en-GB"), ("en-CA", "en-CA"), ("en-AU", "en-AU"),
            ("en-IN", "en-IN"), ("de-DE", "de-DE"), ("de-AT", "de-AT"), ("de-CH", "de-CH"), ("fr-FR", "fr-FR"), ("es-ES", "es-ES"),
            ("es-MX", "es-MX"), ("it-IT", "it-IT"), ("nl-NL", "nl-NL"), ("sv-SE", "sv-SE"), ("pt-BR", "pt-BR"), ("ja-JP", "ja-JP")));
    public static readonly SearchProviderOption BingStrictSafeSearch = Switch("bingStrictSafeSearch", "Strict SafeSearch",
        new AddsParameter("adlt", "strict"));
    public static readonly SearchProviderOption BraveHidesAIAnswers = Switch("braveHidesAIAnswers", "Hide AI Answers",
        new AddsParameter("summary", "0"));
    public static readonly SearchProviderOption BraveSafeSearch = Menu("braveSafeSearch", "Safe Search", (SearchChoice.Moderate, []),
        (SearchChoice.Strict, [new AddsParameter("safesearch", "strict")]), (SearchChoice.Off, [new AddsParameter("safesearch", "off")]));
    public static readonly SearchProviderOption BraveCountry = Places("braveCountry", "Country", namesRegions: true, follows: null,
        code => new AddsParameter("country", code), Codes(("us", "en-US"), ("gb", "en-GB"), ("ca", "en-CA"), ("au", "en-AU"), ("in", "en-IN"),
            ("de", "de-DE"), ("at", "de-AT"), ("ch", "de-CH"), ("fr", "fr-FR"), ("es", "es-ES"), ("mx", "es-MX"), ("it", "it-IT"),
            ("nl", "nl-NL"), ("se", "sv-SE"), ("br", "pt-BR"), ("jp", "ja-JP")));
    public static readonly SearchProviderOption StartpageSafeSearch = Menu("startpageSafeSearch", "Safe Search", (SearchChoice.Moderate, []),
        (SearchChoice.Strict, [new AddsParameter("qadf", "heavy")]), (SearchChoice.Off, [new AddsParameter("qadf", "none")]));
    public static readonly SearchProviderOption KagiExactWords = Switch("kagiExactWords", "Exact Words", new AddsParameter("verbatim", "1"));
    public static readonly SearchProviderOption YahooStrictSafeSearch = Switch("yahooStrictSafeSearch", "Strict SafeSearch",
        new AddsParameter("vm", "r"));
    public static readonly SearchProviderOption QwantRegion = Places("qwantRegion", "Region", namesRegions: false, follows: null,
        code => new AddsParameter("locale", code), Codes(("en_US", "en-US"), ("en_GB", "en-GB"), ("de_DE", "de-DE"), ("de_AT", "de-AT"),
            ("de_CH", "de-CH"), ("fr_FR", "fr-FR"), ("fr_BE", "fr-BE"), ("fr_CH", "fr-CH"), ("es_ES", "es-ES"), ("it_IT", "it-IT"),
            ("nl_NL", "nl-NL"), ("pt_PT", "pt-PT")));
    public static readonly SearchProviderOption ChatGPTSearchesWeb = Switch("chatGPTSearchesWeb", "Search the Web",
        new AddsParameter("hints", "search"));
    public static readonly SearchProviderOption ChatGPTTemporaryChat = Switch("chatGPTTemporaryChat", "Temporary Chat",
        new AddsParameter("temporary-chat", "true"));
    public static readonly SearchProviderOption ChatGPTModel = Text("chatGPTModel", "Model", parameter: "model", example: "gpt-5");
    public static readonly SearchProviderOption KagiAssistantModel = Text("kagiAssistantModel", "Model", parameter: "profile", example: "claude-4-sonnet");
    public static readonly SearchProviderOption KagiAssistantWebAccess = Switch("kagiAssistantWebAccess", "Web Access",
        new AddsParameter("internet", "true"));
    public static readonly SearchProviderOption YouTubeShows = Menu("youTubeShows", "Show", (SearchChoice.Everything, []),
        (SearchChoice.Videos, [new AddsParameter("sp", "EgIQAQ%3D%3D")]), (SearchChoice.Shorts, [new AddsParameter("sp", "EgIQCQ%3D%3D")]),
        (SearchChoice.Channels, [new AddsParameter("sp", "EgIQAg%3D%3D")]), (SearchChoice.Playlists, [new AddsParameter("sp", "EgIQAw%3D%3D")]));
    public static readonly SearchProviderOption WikipediaLanguage = Places("wikipediaLanguage", "Language", namesRegions: false,
        follows: Speaking, code => new FillsSlot(SearchSlot.Language, code), Languages("en", "de", "fr", "es", "it", "ja", "ru", "pt", "zh",
            "nl", "pl", "sv", "ar", "uk", "ko", "he", "tr", "cs", "fi", "no", "da", "id", "vi", "fa", "hu", "ca", "el", "ro"));
    public static readonly SearchProviderOption WikipediaListsResults = Switch("wikipediaListsResults", "Always List Results",
        new AddsParameter("fulltext", "1"));
    public static readonly SearchProviderOption GitHubSearchesFor = Menu("gitHubSearchesFor", "Search For",
        (SearchChoice.Repositories, [new AddsParameter("type", "repositories")]), (SearchChoice.Code, [new AddsParameter("type", "code")]),
        (SearchChoice.Issues, [new AddsParameter("type", "issues")]), (SearchChoice.PullRequests, [new AddsParameter("type", "pullrequests")]),
        (SearchChoice.Discussions, [new AddsParameter("type", "discussions")]), (SearchChoice.Users, [new AddsParameter("type", "users")]));
    public static readonly SearchProviderOption GitHubSort = Menu("gitHubSort", "Sort By", (SearchChoice.BestMatch, []),
        (SearchChoice.MostStars, [new AddsParameter("s", "stars"), new AddsParameter("o", "desc")]),
        (SearchChoice.RecentlyUpdated, [new AddsParameter("s", "updated"), new AddsParameter("o", "desc")]));
    public static readonly SearchProviderOption XLatestFirst = Switch("xLatestFirst", "Latest First", new AddsParameter("f", "live"));
    public static readonly SearchProviderOption StackOverflowSort = Menu("stackOverflowSort", "Sort By", (SearchChoice.Relevance, []),
        (SearchChoice.Newest, [new AddsParameter("tab", "newest")]), (SearchChoice.MostVotes, [new AddsParameter("tab", "votes")]));
    public static readonly SearchProviderOption MDNLanguage = Places("mdnLanguage", "Language", namesRegions: false, follows: Speaking,
        code => new FillsSlot(SearchSlot.Locale, code), Languages("en-US", "de", "es", "fr", "ja", "ko", "pt-BR", "ru", "zh-CN", "zh-TW"));
    public static readonly SearchProviderOption AmazonStore = Places("amazonStore", "Store", namesRegions: true, follows: LivingIn,
        code => new FillsSlot(SearchSlot.Store, code), [Store("amazon.com", "en-US"), Store("amazon.co.uk", "en-GB", "IE"),
            Store("amazon.de", "de-DE", "AT", "CH", "LU"), Store("amazon.fr", "fr-FR"), Store("amazon.com.be", "nl-BE"),
            Store("amazon.it", "it-IT"), Store("amazon.es", "es-ES"), Store("amazon.nl", "nl-NL"), Store("amazon.se", "sv-SE"),
            Store("amazon.pl", "pl-PL"), Store("amazon.co.jp", "ja-JP"), Store("amazon.ca", "en-CA"), Store("amazon.com.au", "en-AU"),
            Store("amazon.in", "en-IN"), Store("amazon.com.br", "pt-BR"), Store("amazon.com.mx", "es-MX")]);
    public static readonly SearchProviderOption IMDbFinds = Menu("imdbFinds", "Find", (SearchChoice.Everything, []),
        (SearchChoice.Titles, [new AddsParameter("s", "tt")]), (SearchChoice.People, [new AddsParameter("s", "nm")]),
        (SearchChoice.Companies, [new AddsParameter("s", "co")]), (SearchChoice.Keywords, [new AddsParameter("s", "kw")]));
    public static readonly SearchProviderOption SpotifyShows = Menu("spotifyShows", "Show", (SearchChoice.Everything, []),
        (SearchChoice.Songs, [new FillsSlot(SearchSlot.Category, "/tracks")]), (SearchChoice.Artists, [new FillsSlot(SearchSlot.Category, "/artists")]),
        (SearchChoice.Albums, [new FillsSlot(SearchSlot.Category, "/albums")]),
        (SearchChoice.Playlists, [new FillsSlot(SearchSlot.Category, "/playlists")]),
        (SearchChoice.Podcasts, [new FillsSlot(SearchSlot.Category, "/podcastAndEpisodes")]));
    public static readonly SearchProviderOption AppleMapsShows = Menu("appleMapsShows", "Map", (SearchChoice.Explore, []),
        (SearchChoice.Satellite, [new AddsParameter("map", "satellite")]), (SearchChoice.Hybrid, [new AddsParameter("map", "hybrid")]),
        (SearchChoice.Transit, [new AddsParameter("map", "transit")]));
    public static readonly SearchProviderOption GoogleImagesSafeSearch = Switch("googleImagesSafeSearch", "SafeSearch",
        new AddsParameter("safe", "active"));
    public static readonly SearchProviderOption TranslateInto = Places("translateInto", "Translate Into", namesRegions: false, follows: Speaking,
        code => new FillsSlot(SearchSlot.Language, code), Languages("en", "de", "fr", "es", "it", "ja", "ko", "zh-CN", "zh-TW", "pt", "ru",
            "nl", "pl", "sv", "ar", "hi", "tr", "uk"));
    public static readonly SearchProviderOption HackerNewsSort = Menu("hackerNewsSort", "Sort By", (SearchChoice.Popular, []),
        (SearchChoice.Newest, [new AddsParameter("sort", "byDate")]));
    public static readonly SearchProviderOption HackerNewsShows = Menu("hackerNewsShows", "Show", (SearchChoice.Everything, []),
        (SearchChoice.Stories, [new AddsParameter("type", "story")]), (SearchChoice.Comments, [new AddsParameter("type", "comment")]));
    public static readonly SearchProviderOption AppleDeveloperSkipsAI = Switch("appleDeveloperSkipsAI", "Skip the AI Answer",
        new AddsParameter("tab", "search"));

    /// Every option, in the order they were added.
    public static IReadOnlyList<SearchProviderOption> All { get; } = [GoogleHidesAIOverviews, GoogleSafeSearch, GoogleExactWords, DuckDuckGoHidesAI,
        DuckDuckGoSafeSearch, DuckDuckGoRegion, BingMarket, BingStrictSafeSearch, BraveHidesAIAnswers, BraveSafeSearch, BraveCountry,
        StartpageSafeSearch, KagiExactWords, YahooStrictSafeSearch, QwantRegion, ChatGPTSearchesWeb, ChatGPTTemporaryChat, ChatGPTModel,
        KagiAssistantModel, KagiAssistantWebAccess, YouTubeShows, WikipediaLanguage, WikipediaListsResults, GitHubSearchesFor, GitHubSort,
        XLatestFirst, StackOverflowSort, MDNLanguage, AmazonStore, IMDbFinds, SpotifyShows, AppleMapsShows, GoogleImagesSafeSearch,
        TranslateInto, HackerNewsSort, HackerNewsShows, AppleDeveloperSkipsAI];

    #endregion

    #region Variables

    public string Name { get; }

    /// What Settings calls the option, under its provider.
    [Localized]
    public string Title { get; }

    /// The option is a switch, on while it keeps `On`.
    public bool IsSwitch { get; }

    /// The option takes text a person types, as a model's name.
    public bool AcceptsText { get; }

    /// An example of the text the option takes, which its empty field shows.
    public string? TextExample { get; }

    /// The menu's choices, the first of them its default.
    public IReadOnlyList<SearchChoice> Choices { get; }

    /// The languages, regions or stores the option's menu offers after
    /// Automatic, which leaves the choice to this device or to the site.
    public IReadOnlyList<SearchLocaleCode> Locales { get; }

    /// Settings names the option's places by their region, as a country or
    /// store, rather than by their language.
    public bool NamesRegions { get; }

    /// What a value of the option does to its provider's address on a device
    /// in a locale: nothing for a blank value, unless the option follows the
    /// device.
    private readonly Func<string?, SearchLocale, IEnumerable<SearchEdit>> edits;

    #endregion

    #region Constructors

    private SearchProviderOption(string name, string title, bool isSwitch, bool acceptsText, string? textExample, IReadOnlyList<SearchChoice> choices,
        IReadOnlyList<SearchLocaleCode> locales, bool namesRegions, Func<string?, SearchLocale, IEnumerable<SearchEdit>> edits) {
        Name = name;
        Title = title;
        IsSwitch = isSwitch;
        AcceptsText = acceptsText;
        TextExample = textExample;
        Choices = choices;
        Locales = locales;
        NamesRegions = namesRegions;
        this.edits = edits;
    }

    /// A switch that makes `whenOn` while it is on.
    private static SearchProviderOption Switch(string name, string title, params SearchEdit[] whenOn) =>
        new(name, title, isSwitch: true, acceptsText: false, textExample: null, choices: [], locales: [], namesRegions: false,
            (value, _) => value == On ? whenOn : []);

    /// A menu whose first choice is its default, each choice making its own edits.
    private static SearchProviderOption Menu(string name, string title, params (SearchChoice Choice, SearchEdit[] Edits)[] choices) =>
        new(name, title, isSwitch: false, acceptsText: false, textExample: null, [.. choices.Select(entry => entry.Choice)], locales: [],
            namesRegions: false,
            (value, _) => (choices.FirstOrDefault(entry => entry.Choice.Name == value).Edits ?? choices[0].Edits));

    /// Text a person types, which sets `parameter` to it when it is not blank.
    private static SearchProviderOption Text(string name, string title, string parameter, string example) =>
        new(name, title, isSwitch: false, acceptsText: true, example, choices: [], locales: [], namesRegions: false,
            (value, _) => string.IsNullOrWhiteSpace(value) ? [] : [new AddsParameter(parameter, Uri.EscapeDataString(value.Trim()))]);

    /// A menu of places, each making `place` of its code. Automatic takes the
    /// first place that `follows` the device, or leaves the address as it is.
    private static SearchProviderOption Places(string name, string title, bool namesRegions, Func<SearchLocale, SearchLocaleCode, bool>? follows,
        Func<string, SearchEdit> place, IReadOnlyList<SearchLocaleCode> codes) =>
        new(name, title, isSwitch: false, acceptsText: false, textExample: null, choices: [], codes, namesRegions,
            (value, locale) => (codes.FirstOrDefault(code => code.Code == value)
                ?? (follows is null ? null : codes.FirstOrDefault(code => follows(locale, code)))) is { } chosen ? [place(chosen.Code)] : []);

    private static IReadOnlyList<SearchLocaleCode> Codes(params (string Code, string Locale)[] codes) =>
        [.. codes.Select(code => new SearchLocaleCode(code.Code, code.Locale, []))];

    private static IReadOnlyList<SearchLocaleCode> Languages(params string[] codes) => [.. codes.Select(code => new SearchLocaleCode(code, code, []))];

    private static SearchLocaleCode Store(string host, string locale, params string[] alsoServes) => new(host, locale, alsoServes);

    private static bool Speaking(SearchLocale locale, SearchLocaleCode code) => locale.Speaks(code.Locale);

    private static bool LivingIn(SearchLocale locale, SearchLocaleCode code) => locale.LivesIn(code.Locale, code.AlsoServes);

    #endregion

    #region Actions - Lookup

    public static SearchProviderOption? Named(string? name) => All.FirstOrDefault(option => option.Name == name);

    #endregion

    #region Actions - Values

    /// Whether the option keeps `value`: `On` for a switch, one of its
    /// choices or places by name or code, or short text without line breaks.
    public bool Admits(string value) {
        ArgumentNullException.ThrowIfNull(value);
        if (IsSwitch) return value == On;
        if (AcceptsText) return value.Length <= MaximumTextLength && !value.Any(char.IsControl);
        return Choices.Any(choice => choice.Name == value) || Locales.Any(code => code.Code == value);
    }

    /// What `value`, or the default when it is null, does to the provider's
    /// address on a device in `locale`.
    internal IEnumerable<SearchEdit> Edits(string? value, SearchLocale locale) => edits(value, locale);

    #endregion
}
