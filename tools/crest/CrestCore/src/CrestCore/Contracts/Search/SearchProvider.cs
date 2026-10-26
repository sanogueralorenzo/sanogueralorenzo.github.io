using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A built-in search engine and its optional first-party suggestions endpoint.
public sealed class SearchProvider {
    #region Static Variables

    public static readonly SearchProvider Google = new("google", "Google", "https://www.google.com/search?q=%s",
        "https://www.google.com/complete/search?client=chrome&q=%s", 0x4285F4, "SearchProviderGoogle");
    public static readonly SearchProvider DuckDuckGo = new("duckDuckGo", "DuckDuckGo", "https://duckduckgo.com/?q=%s",
        "https://duckduckgo.com/ac/?q=%s&type=list", 0xDE5833, "SearchProviderDuckDuckGo");
    public static readonly SearchProvider Bing = new("bing", "Bing", "https://www.bing.com/search?q=%s",
        "https://www.bing.com/osjson.aspx?query=%s", 0x0C8484, "SearchProviderBing");
    public static readonly SearchProvider Brave = new("brave", "Brave Search", "https://search.brave.com/search?q=%s",
        "https://search.brave.com/api/suggest?q=%s", 0xFB542B, "SearchProviderBrave");

    public static IReadOnlyList<SearchProvider> All { get; } = [Google, DuckDuckGo, Bing, Brave];

    #endregion

    #region Variables

    public string Name { get; }
    public string Title { get; }
    public BrandColor Color { get; }
    public string Logo { get; }
    public string SearchTemplate => search.Pattern;
    private readonly SearchTemplate search;
    private readonly SearchTemplate? suggestions;

    #endregion

    #region Constructors

    private SearchProvider(string name, string title, string search, string? suggestions, int color, string logo) {
        Name = name;
        Title = title;
        Color = new(((color >> 16) & 255) / 255.0, ((color >> 8) & 255) / 255.0, (color & 255) / 255.0);
        Logo = logo;
        this.search = new(search);
        this.suggestions = suggestions is null ? null : new(suggestions);
    }

    #endregion

    #region Actions - Lookup

    public static SearchProvider? Named(string? name) => All.FirstOrDefault(provider => provider.Name == name);

    #endregion

    #region Actions - Searching

    /// Encodes query text once into this provider's search address.
    public string Search(string query) => search.Render(query);

    /// The provider's suggestions address, or null when it offers none.
    public string? Suggest(string query) => suggestions?.Render(query);

    #endregion
}
