using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A search provider Crest ships: a search engine, an AI assistant or a
/// website, each describing itself whole: its brand, the shortcuts that name
/// it in the palette, its search address and suggestions, the options a
/// person may set for it, and whether a device that never chose offers it.
/// A device may turn any of them off, give one its own shortcuts and set its
/// options; the provider then searches the address its options make.
///
/// A Space stores and syncs a built-in choice as the provider's `Name`, which
/// never changes. A provider travels as its index in `All`, so `All` only
/// grows at the end.
public sealed class BuiltInSearchProvider {
    #region Static Variables

    public static readonly BuiltInSearchProvider Google = new(name: "google", title: "Google", SearchProviderKind.Engine, ["g", "google"],
        "https://www.google.com/search?q=%s", suggestions: "https://www.google.com/complete/search?client=chrome&q=%s", color: 0x4285F4,
        logo: "SearchProviderGoogle", isEnabledByDefault: true,
        options: [SearchProviderOption.GoogleHidesAIOverviews, SearchProviderOption.GoogleSafeSearch, SearchProviderOption.GoogleExactWords]);
    public static readonly BuiltInSearchProvider DuckDuckGo = new(name: "duckDuckGo", title: "DuckDuckGo", SearchProviderKind.Engine,
        ["ddg", "dg", "duck"], "https://{host}/?q=%s", suggestions: "https://duckduckgo.com/ac/?q=%s&type=list", color: 0xDE5833,
        logo: "SearchProviderDuckDuckGo", isEnabledByDefault: true,
        options: [SearchProviderOption.DuckDuckGoHidesAI, SearchProviderOption.DuckDuckGoSafeSearch, SearchProviderOption.DuckDuckGoRegion],
        slots: [SearchSlot.Host.Holding("duckduckgo.com")]);
    public static readonly BuiltInSearchProvider Bing = new(name: "bing", title: "Bing", SearchProviderKind.Engine, ["b", "bing"],
        "https://www.bing.com/search?q=%s", suggestions: "https://www.bing.com/osjson.aspx?query=%s", color: 0x0C8484,
        logo: "SearchProviderBing", isEnabledByDefault: true, options: [SearchProviderOption.BingMarket, SearchProviderOption.BingStrictSafeSearch]);
    public static readonly BuiltInSearchProvider Ecosia = new(name: "ecosia", title: "Ecosia", SearchProviderKind.Engine, ["ecosia", "eco"],
        "https://www.ecosia.org/search?q=%s", suggestions: "https://ac.ecosia.org/autocomplete?q=%s&type=list", color: 0x2C8C4A,
        logo: "SearchProviderEcosia", isEnabledByDefault: true, options: []);
    public static readonly BuiltInSearchProvider Brave = new(name: "brave", title: "Brave Search", SearchProviderKind.Engine, ["brave"],
        "https://search.brave.com/search?q=%s", suggestions: "https://search.brave.com/api/suggest?q=%s", color: 0xFB542B,
        logo: "SearchProviderBrave", isEnabledByDefault: true,
        options: [SearchProviderOption.BraveHidesAIAnswers, SearchProviderOption.BraveSafeSearch, SearchProviderOption.BraveCountry]);
    public static readonly BuiltInSearchProvider Startpage = new(name: "startpage", title: "Startpage", SearchProviderKind.Engine,
        ["sp", "startpage"], "https://www.startpage.com/sp/search?query=%s", suggestions: "https://www.startpage.com/osuggestions?q=%s",
        color: 0x6573FF, logo: null, isEnabledByDefault: true, options: [SearchProviderOption.StartpageSafeSearch]);
    public static readonly BuiltInSearchProvider Kagi = new(name: "kagi", title: "Kagi", SearchProviderKind.Engine, ["kagi"],
        "https://kagi.com/search?q=%s", suggestions: "https://kagisuggest.com/api/autosuggest?q=%s", color: 0xFFB319, logo: null,
        isEnabledByDefault: false, options: [SearchProviderOption.KagiExactWords]);
    public static readonly BuiltInSearchProvider Yahoo = new(name: "yahoo", title: "Yahoo", SearchProviderKind.Engine, ["y", "yahoo"],
        "https://search.yahoo.com/search?p=%s", suggestions: "https://search.yahoo.com/sugg/os?command=%s&output=fxjson", color: 0x6001D2,
        logo: null, isEnabledByDefault: false, options: [SearchProviderOption.YahooStrictSafeSearch]);
    public static readonly BuiltInSearchProvider Qwant = new(name: "qwant", title: "Qwant", SearchProviderKind.Engine, ["qw", "qwant"],
        "https://www.qwant.com/?q=%s", suggestions: "https://api.qwant.com/v3/suggest/?q=%s&client=opensearch", color: 0x5C97FF, logo: null,
        isEnabledByDefault: false, options: [SearchProviderOption.QwantRegion]);
    public static readonly BuiltInSearchProvider ChatGPT = new(name: "chatGPT", title: "ChatGPT", SearchProviderKind.Assistant,
        ["chatgpt", "gpt"], "https://chatgpt.com/?q=%s", suggestions: null, color: 0x10A37F, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.ChatGPTSearchesWeb, SearchProviderOption.ChatGPTTemporaryChat, SearchProviderOption.ChatGPTModel]);
    public static readonly BuiltInSearchProvider Claude = new(name: "claude", title: "Claude", SearchProviderKind.Assistant, ["claude"],
        "https://claude.ai/new?q=%s", suggestions: null, color: 0xD97757, logo: null, isEnabledByDefault: true, options: []);
    public static readonly BuiltInSearchProvider Perplexity = new(name: "perplexity", title: "Perplexity", SearchProviderKind.Assistant,
        ["perplexity", "pplx"], "https://www.perplexity.ai/search?q=%s", suggestions: null, color: 0x20B8CD, logo: null,
        isEnabledByDefault: true, options: []);
    public static readonly BuiltInSearchProvider GoogleAIMode = new(name: "googleAIMode", title: "Google AI Mode",
        SearchProviderKind.Assistant, ["aimode", "gai"], "https://www.google.com/search?udm=50&q=%s",
        suggestions: "https://www.google.com/complete/search?client=chrome&q=%s", color: 0x4285F4, logo: null, isEnabledByDefault: true,
        options: []);
    public static readonly BuiltInSearchProvider Grok = new(name: "grok", title: "Grok", SearchProviderKind.Assistant, ["grok"],
        "https://grok.com/?q=%s", suggestions: null, color: 0x71767B, logo: null, isEnabledByDefault: false, options: []);
    public static readonly BuiltInSearchProvider LeChat = new(name: "leChat", title: "Le Chat", SearchProviderKind.Assistant,
        ["mistral", "lechat"], "https://chat.mistral.ai/chat?q=%s", suggestions: null, color: 0xFA520F, logo: null,
        isEnabledByDefault: false, options: []);
    public static readonly BuiltInSearchProvider DuckAI = new(name: "duckAI", title: "Duck.ai", SearchProviderKind.Assistant,
        ["duckai", "ai"], "https://duckduckgo.com/?q=%s&ia=chat", suggestions: null, color: 0xDE5833, logo: null, isEnabledByDefault: false,
        options: []);
    public static readonly BuiltInSearchProvider CopilotSearch = new(name: "copilotSearch", title: "Copilot Search",
        SearchProviderKind.Assistant, ["copilot"], "https://www.bing.com/copilotsearch?q=%s",
        suggestions: "https://www.bing.com/osjson.aspx?query=%s", color: 0x2870EA, logo: null, isEnabledByDefault: false, options: []);
    public static readonly BuiltInSearchProvider KagiAssistant = new(name: "kagiAssistant", title: "Kagi Assistant",
        SearchProviderKind.Assistant, ["kagiai"], "https://kagi.com/assistant?q=%s", suggestions: null, color: 0xFFB319, logo: null,
        isEnabledByDefault: false, options: [SearchProviderOption.KagiAssistantModel, SearchProviderOption.KagiAssistantWebAccess]);
    public static readonly BuiltInSearchProvider YouTube = new(name: "youTube", title: "YouTube", SearchProviderKind.Website, ["yt", "youtube"],
        "https://www.youtube.com/results?search_query=%s",
        suggestions: "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=%s", color: 0xFF0000, logo: null,
        isEnabledByDefault: true, options: [SearchProviderOption.YouTubeShows]);
    public static readonly BuiltInSearchProvider Wikipedia = new(name: "wikipedia", title: "Wikipedia", SearchProviderKind.Website,
        ["w", "wiki"], "https://{language}.wikipedia.org/wiki/Special:Search?search=%s",
        suggestions: "https://{language}.wikipedia.org/w/api.php?action=opensearch&search=%s&format=json", color: 0x636466, logo: null,
        isEnabledByDefault: true, options: [SearchProviderOption.WikipediaLanguage, SearchProviderOption.WikipediaListsResults],
        slots: [SearchSlot.Language.Holding("en")]);
    public static readonly BuiltInSearchProvider GitHub = new(name: "gitHub", title: "GitHub", SearchProviderKind.Website, ["gh", "github"],
        "https://github.com/search?q=%s", suggestions: null, color: 0x8250DF, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.GitHubSearchesFor, SearchProviderOption.GitHubSort]);
    public static readonly BuiltInSearchProvider Reddit = new(name: "reddit", title: "Reddit", SearchProviderKind.Website, ["r", "reddit"],
        "https://www.reddit.com/search/?q=%s", suggestions: null, color: 0xFF4500, logo: null, isEnabledByDefault: true, options: []);
    public static readonly BuiltInSearchProvider X = new(name: "x", title: "X", SearchProviderKind.Website, ["x", "twitter"],
        "https://x.com/search?q=%s&src=typed_query", suggestions: null, color: 0x71767B, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.XLatestFirst]);
    public static readonly BuiltInSearchProvider StackOverflow = new(name: "stackOverflow", title: "Stack Overflow",
        SearchProviderKind.Website, ["so", "stackoverflow"], "https://stackoverflow.com/search?q=%s", suggestions: null, color: 0xF48024,
        logo: null, isEnabledByDefault: true, options: [SearchProviderOption.StackOverflowSort]);
    public static readonly BuiltInSearchProvider MDN = new(name: "mdn", title: "MDN", SearchProviderKind.Website, ["mdn"],
        "https://developer.mozilla.org/{locale}/search?q=%s", suggestions: null, color: 0x83D0F2, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.MDNLanguage], slots: [SearchSlot.Locale.Holding("en-US")]);
    public static readonly BuiltInSearchProvider Amazon = new(name: "amazon", title: "Amazon", SearchProviderKind.Website, ["a", "amazon"],
        "https://www.{store}/s?k=%s", suggestions: null, color: 0xFF9900, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.AmazonStore], slots: [SearchSlot.Store.Holding("amazon.com")]);
    public static readonly BuiltInSearchProvider IMDb = new(name: "imdb", title: "IMDb", SearchProviderKind.Website, ["imdb"],
        "https://www.imdb.com/find/?q=%s", suggestions: null, color: 0xF5C518, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.IMDbFinds]);
    public static readonly BuiltInSearchProvider Spotify = new(name: "spotify", title: "Spotify", SearchProviderKind.Website, ["spotify"],
        "https://open.spotify.com/search/%s{category}", suggestions: null, color: 0x1DB954, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.SpotifyShows], slots: [SearchSlot.Category.Holding("")]);
    public static readonly BuiltInSearchProvider FigmaCommunity = new(name: "figmaCommunity", title: "Figma Community",
        SearchProviderKind.Website, ["figma"],
        "https://www.figma.com/community/search?query=%s&resource_type=mixed&sort_by=relevancy&editor_type=all", suggestions: null,
        color: 0xF24E1E, logo: null, isEnabledByDefault: true, options: []);
    public static readonly BuiltInSearchProvider GoogleMaps = new(name: "googleMaps", title: "Google Maps", SearchProviderKind.Website,
        ["gm", "maps"], "https://www.google.com/maps/search/?api=1&query=%s", suggestions: null, color: 0x34A853, logo: null,
        isEnabledByDefault: true, options: []);
    public static readonly BuiltInSearchProvider AppleMaps = new(name: "appleMaps", title: "Apple Maps", SearchProviderKind.Website,
        ["amaps"], "https://maps.apple.com/search?query=%s", suggestions: null, color: 0x59B94C, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.AppleMapsShows]);
    public static readonly BuiltInSearchProvider GoogleImages = new(name: "googleImages", title: "Google Images", SearchProviderKind.Website,
        ["gi", "images"], "https://www.google.com/search?udm=2&q=%s",
        suggestions: "https://www.google.com/complete/search?client=chrome&q=%s", color: 0x4285F4, logo: null, isEnabledByDefault: true,
        options: [SearchProviderOption.GoogleImagesSafeSearch]);
    public static readonly BuiltInSearchProvider GoogleTranslate = new(name: "googleTranslate", title: "Google Translate",
        SearchProviderKind.Website, ["gt", "translate"], "https://translate.google.com/?sl=auto&tl={language}&text=%s&op=translate",
        suggestions: null, color: 0x4285F4, logo: null, isEnabledByDefault: true, options: [SearchProviderOption.TranslateInto],
        slots: [SearchSlot.Language.Holding("en")]);
    public static readonly BuiltInSearchProvider WolframAlpha = new(name: "wolframAlpha", title: "Wolfram|Alpha", SearchProviderKind.Website,
        ["wa", "wolfram"], "https://www.wolframalpha.com/input?i=%s", suggestions: null, color: 0xDD1100, logo: null,
        isEnabledByDefault: true, options: []);
    public static readonly BuiltInSearchProvider HackerNews = new(name: "hackerNews", title: "Hacker News", SearchProviderKind.Website,
        ["hn"], "https://hn.algolia.com/?query=%s", suggestions: null, color: 0xFF6600, logo: null, isEnabledByDefault: false,
        options: [SearchProviderOption.HackerNewsSort, SearchProviderOption.HackerNewsShows]);
    public static readonly BuiltInSearchProvider Npm = new(name: "npm", title: "npm", SearchProviderKind.Website, ["npm"],
        "https://www.npmjs.com/search?q=%s", suggestions: null, color: 0xCB3837, logo: null, isEnabledByDefault: false, options: []);
    public static readonly BuiltInSearchProvider AppleDeveloper = new(name: "appleDeveloper", title: "Apple Developer",
        SearchProviderKind.Website, ["adev"], "https://developer.apple.com/search/?q=%s", suggestions: null, color: 0x0071E3, logo: null,
        isEnabledByDefault: false, options: [SearchProviderOption.AppleDeveloperSkipsAI]);

    /// Every built-in, in the order Settings lists them within their kind.
    public static IReadOnlyList<BuiltInSearchProvider> All { get; } = [Google, DuckDuckGo, Bing, Ecosia, Brave, Startpage, Kagi, Yahoo,
        Qwant, ChatGPT, Claude, Perplexity, GoogleAIMode, Grok, LeChat, DuckAI, CopilotSearch, KagiAssistant, YouTube, Wikipedia, GitHub,
        Reddit, X, StackOverflow, MDN, Amazon, IMDb, Spotify, FigmaCommunity, GoogleMaps, AppleMaps, GoogleImages, GoogleTranslate,
        WolframAlpha, HackerNews, Npm, AppleDeveloper];

    #endregion

    #region Variables

    public string Name { get; }

    /// The provider's brand, as people know it.
    public string Title { get; }

    public SearchProviderKind Kind { get; }

    /// The words that name the provider in the palette before Tab, its main
    /// one first, until a person gives it their own.
    public IReadOnlyList<string> Shortcuts { get; }

    /// The color of the provider's brand, which its chip and the palette's
    /// glow wear.
    public BrandColor Color { get; }

    /// The asset catalog image that stands for the provider, or null when its
    /// site's own icon does.
    public string? Logo { get; }

    /// Whether a device that never chose offers the provider.
    public bool IsEnabledByDefault { get; }

    /// The settings a person may change for the provider, in the order
    /// Settings shows them.
    public IReadOnlyList<SearchProviderOption> Options { get; }

    /// The search address, with its placeholder and any slots its options fill.
    private readonly SearchTemplate search;

    /// The address of the suggestions it offers as a person types, or null for none.
    private readonly SearchTemplate? suggestions;

    /// What each slot of its addresses holds when no option fills it.
    private readonly IReadOnlyList<SearchSlotDefault> slots;

    #endregion

    #region Constructors

    private BuiltInSearchProvider(string name, string title, SearchProviderKind kind, IReadOnlyList<string> shortcuts, string search,
        string? suggestions, int color, string? logo, bool isEnabledByDefault, IReadOnlyList<SearchProviderOption> options,
        IReadOnlyList<SearchSlotDefault>? slots = null) {
        Name = name;
        Title = title;
        Kind = kind;
        Shortcuts = shortcuts;
        Color = new(((color >> 16) & 255) / 255.0, ((color >> 8) & 255) / 255.0, (color & 255) / 255.0);
        Logo = logo;
        IsEnabledByDefault = isEnabledByDefault;
        Options = options;
        this.search = new(search);
        this.suggestions = suggestions is null ? null : new(suggestions);
        this.slots = slots ?? [];
    }

    #endregion

    #region Actions - Lookup

    public static BuiltInSearchProvider? Named(string? name) => All.FirstOrDefault(provider => provider.Name == name);

    #endregion

    #region Actions - Resolving

    /// The provider as a device searches with it: answering to `shortcuts`,
    /// with each of its options at the value `chosen` keeps, or its default,
    /// for a device in `locale`.
    internal SearchProvider Resolved(IReadOnlyList<string> shortcuts, IReadOnlyList<SearchOptionSetting> chosen, SearchLocale locale) {
        var edits = Options.SelectMany(option => option.Edits(chosen.FirstOrDefault(setting => setting.Option == option)?.Value, locale))
            .ToList();
        return new(Name, Title, Kind, shortcuts, search.Edited(edits, slots).Pattern,
            suggestions?.Edited(edits.Where(edit => edit.ReachesSuggestions), slots).Pattern, Color, Logo, BuiltIn: this, CustomId: null);
    }

    #endregion
}
