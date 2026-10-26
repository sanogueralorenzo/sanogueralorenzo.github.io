using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// What a search provider searches: a query rendered once into its address,
/// every built-in with every value of every option making an address Crest
/// opens, options editing only their own provider's address, and the rules a
/// provider a person adds must pass to join the catalog.
public sealed class SearchPolicyTests {
    private static readonly Guid KagiId = Guid.Parse("00000000-0000-0000-0000-000000000264");

    private static SearchCatalog Catalog(string? language = "en", string? region = "US") => SearchCatalog.Starting(language, region);

    /// A provider a person added, as they typed it.
    private static CustomSearchProvider Added(string name, string search, string? suggestions = null, Guid? id = null,
        params string[] shortcuts) => new(id ?? KagiId, name, search, suggestions, SearchProviderKind.Engine, shortcuts, Color: null);

    /// The rule saving `provider` into `catalog` breaks, or null when it is saved.
    private static Rejection? Refusal(SearchCatalog catalog, CustomSearchProvider provider) {
        try {
            catalog.Saving(provider);
            return null;
        } catch (Rejected rejected) {
            return rejected.Rejection;
        }
    }

    [Theory]
    [InlineData("native mac browser", "native%20mac%20browser")]
    [InlineData("a+b", "a%2Bb")]
    [InlineData("fish & chips=good", "fish%20%26%20chips%3Dgood")]
    [InlineData("C# #tag", "C%23%20%23tag")]
    [InlineData("Café 日本", "Caf%C3%A9%20%E6%97%A5%E6%9C%AC")]
    [InlineData("🦊", "%F0%9F%A6%8A")]
    [InlineData("a/b?c", "a%2Fb%3Fc")]
    [InlineData("-._~", "-._~")]
    [InlineData("%s {searchTerms}", "%25s%20%7BsearchTerms%7D")]
    [InlineData("100%", "100%25")]
    [InlineData("", "")]
    public void QueriesArePercentEncodedOnceAsUtf8IntoTheSinglePlaceholder(string query, string encoded) {
        Assert.Equal("https://www.google.com/search?q=" + encoded, Catalog().Resolving(BuiltInSearchProvider.Google).Search(query));
        var kagi = Catalog().Saving(Added("Kagi", "https://kagi.com/find/{searchTerms}?source=crest")).Custom[0];
        Assert.Equal("https://kagi.com/find/" + encoded + "?source=crest", kagi.Provider.Search(query));
    }

    private static IEnumerable<string> Values(SearchProviderOption option) => option.IsSwitch ? [SearchProviderOption.On]
        : option.AcceptsText ? ["gpt-5 mini"]
        : [.. option.Choices.Select(choice => choice.Name), .. option.Locales.Select(code => code.Code)];

    [Theory]
    [InlineData("https://example.com/search?q=%s", "Example", null)]
    [InlineData("  https://example.com/search?q=%s  ", "  Example  ", null)]
    [InlineData("https://example.com:443/search/%s", "Example", null)]
    [InlineData("https://example.com/search?q=%s", "   ", "emptyName")]
    [InlineData("https://example.com/search?q=%s", "12345678901234567890123456789012345678901234567890123456789012345", "nameTooLong")]
    [InlineData("https://example.com/search", "Example", "missingPlaceholder")]
    [InlineData("https://example.com/?q=%s&again=%s", "Example", "ambiguousPlaceholder")]
    [InlineData("https://example.com/?q=%s&again={searchTerms}", "Example", "ambiguousPlaceholder")]
    [InlineData("https://example.com/?q=%s&bad=%zz", "Example", "invalidTemplate")]
    [InlineData("http://example.com/?q=%s", "Example", "requiresHttps")]
    [InlineData("example.com/?q=%s", "Example", "requiresHttps")]
    [InlineData("https://user:password@example.com/?q=%s", "Example", "credentialsInTemplate")]
    [InlineData("https://example.com:8443/?q=%s", "Example", "nonstandardPort")]
    [InlineData("https://%s.example.com/search", "Example", "unsafeHost")]
    [InlineData("https://localhost/search?q=%s", "Example", "unsafeHost")]
    [InlineData("https://printer.local/search?q=%s", "Example", "unsafeHost")]
    [InlineData("https://192.168.1.1/search?q=%s", "Example", "unsafeHost")]
    [InlineData("https://example.com/search#q=%s", "Example", "placeholderInFragment")]
    [InlineData("https://example.com/search?Token=secret&q=%s", "Example", "secretInTemplate")]
    [InlineData("https://example.com/search?api%5Fkey=secret&q=%s", "Example", "secretInTemplate")]
    public void AddedProviderValidationNamesTheRuleThePersonBroke(string template, string name, string? flaw) {
        var provider = Added(name, template, suggestions: "  ");
        Assert.Equal(SearchEngineFlaw.Named(flaw) is { } expected ? new InvalidSearchEngine(expected) : null, Refusal(Catalog(), provider));
        if (flaw is null) Assert.Equal(Added("Example", template.Trim()), Catalog().Saving(provider).Custom.Single());
    }

    [Fact]
    public void ASpaceSearchesWithItsChoiceTheCopyItCarriesOrTheDefault() {
        var (carried, broken) = (Guid.NewGuid(), Guid.NewGuid());
        var catalog = Catalog().Choosing(Catalog().Resolving(BuiltInSearchProvider.Brave));
        BrowsingPreferences Space(BuiltInSearchProvider? builtIn, Guid? custom, bool follows) => new(builtIn, custom,
            [CustomSearchProvider.Carried(broken, "Broken", "http://127.0.0.1/?q=%s", null),
                CustomSearchProvider.Carried(carried, "Carried", "https://carried.example/?q=%s", null)],
            SearchSuggestionsEnabled: true, follows, FollowsDefaultSuggestions: false, CurrentTabCleanup.Never, ContentBlockingPolicy.Balanced,
            new(DataRetention.Forever, DataRetention.Forever, DataRetention.Forever));

        Assert.Equal("brave", catalog.For(Space(BuiltInSearchProvider.Bing, null, follows: true), isPrivate: false).Name);
        Assert.Equal("duckDuckGo", catalog.For(Space(BuiltInSearchProvider.Bing, null, follows: true), isPrivate: true).Name);
        Assert.Equal("bing", catalog.For(Space(BuiltInSearchProvider.Bing, null, follows: false), isPrivate: true).Name);
        Assert.Equal("https://carried.example/?q=a", catalog.For(Space(null, carried, follows: false), isPrivate: false).Search("a"));
        Assert.Equal("brave", catalog.For(Space(null, broken, follows: false), isPrivate: false).Name);
        Assert.True(catalog.SuggestsFor(Space(null, null, follows: true)));
        Assert.IsType<UnsuitableDefaultSearch>(Assert.Throws<Rejected>(() =>
            catalog.Choosing(catalog.Resolving(BuiltInSearchProvider.YouTube))).Rejection);
    }

    [Fact]
    public void TheCatalogSurvivesTheDeviceStore() {
        var assistant = Added("Kagi", "https://kagi.com/search?q=%s", "https://kagi.com/api/autosuggest?q=%s", shortcuts: ["kg"]) with {
            Kind = SearchProviderKind.Assistant,
            Color = new BrandColor(0.5, 0.25, 0.75)
        };
        var catalog = Catalog("fr", "BE")
            .Saving(assistant)
            .Enabling(BuiltInSearchProvider.Reddit, false)
            .Naming(BuiltInSearchProvider.YouTube, ["you"])
            .Setting(BuiltInSearchProvider.Amazon, SearchProviderOption.AmazonStore, "amazon.co.jp")
            .Suggesting(true);
        catalog = catalog.Choosing(catalog.Custom[0].Provider).ChoosingPrivate(catalog.Resolving(BuiltInSearchProvider.Startpage));

        Assert.Equal(catalog, SearchCatalogDocument.Read(SearchCatalogDocument.Write(catalog)));
        Assert.Null(SearchCatalogDocument.Read("[]"));
        // What a later build stored and this one cannot read is left out.
        var later = SearchCatalogDocument.Read("""
            {"default":"youTube","builtIns":[{"name":"future","enabled":true},{"name":"google","enabled":false,
              "options":{"googleSafeSearch":"on","teleport":"on","googleExactWords":"sometimes"}}]}
            """)!;
        Assert.Equal([new SearchOptionSetting(SearchProviderOption.GoogleSafeSearch, SearchProviderOption.On)],
            later.Settings(BuiltInSearchProvider.Google).Options);
        Assert.False(later.Settings(BuiltInSearchProvider.Google).IsEnabled);
        Assert.Equal("google", later.Default.Name);
    }
}
