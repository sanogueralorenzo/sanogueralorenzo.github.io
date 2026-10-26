using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What a window's palette reveals and sends away: it asks a search engine for
/// suggestions by default and never in a private
/// window.
public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("persistent", true)]
    [InlineData("private", false)]
    public void APaletteAsksForGoogleSuggestionsExceptInAPrivateWindow(string kind,
        bool asks) {
        var (document, space, _) = SavedSession();
        var session = document["session"]!;
        using var device = new TestDevice(session, WorkspaceKind.Named(kind));
        var window = device.Open(space);

        var answer = device.Query(Asking(window, "crest browser"));

        Assert.Equal(asks, answer.SuggestionAddress is not null);
        Assert.Null(device.Query(Asking(window, "   ")).SuggestionAddress);
        // Fetched suggestions join the answer the same way in every window.
        var merged = device.Query(Asking(window, "crest browser") with { Remote = ["crest browser download", "Crest Browser"] });
        Assert.Equal(["crest browser download"], merged.Groups.Single(group => group.Section == PaletteSection.SearchSuggestions).Rows
            .Select(row => row.Title));
    }

    [Theory]
    [InlineData("google")]
    [InlineData("duckDuckGo")]
    [InlineData("bing")]
    [InlineData("brave")]
    public void SearchAndSuggestionsUseOnlyTheGlobalProviderAcrossWorkspaces(string name) {
        var provider = SearchProvider.Named(name)!;
        var (document, space, _) = SavedSession();
        var session = document["session"]!;
        using var device = new TestDevice(session);
        device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { SearchProvider = provider }));
        var borrowed = device.Borrow(session["spaces"]![0]!);
        var privateWorkspace = device.Attach(session.DeepClone(), WorkspaceKind.Private);
        foreach (var workspace in new[] { device.Workspace, borrowed, privateWorkspace }) {
            var window = device.OpenIn(workspace, space);
            var answer = device.Query(Asking(window, "crest & browser"));
            var search = answer.Groups.SelectMany(group => group.Rows).Single(row => row.Kind == PaletteRowKind.Search);
            Assert.Same(provider, search.Provider);
            Assert.Equal(provider.Search("crest & browser"), search.Address);
            Assert.Equal(workspace == privateWorkspace ? null : provider.Suggest("crest & browser"), answer.SuggestionAddress);
            foreach (var spaceId in new Guid?[] { space, null })
                Assert.Equal(provider.Search("crest & browser"), device.Query(new ResolveAddress(workspace, spaceId, "crest & browser")).Url);
        }
        // A later choice takes effect immediately for the same window and input.
        var selected = device.Open(space);
        device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { SearchProvider = SearchProvider.Bing }));
        Assert.Equal(SearchProvider.Bing.Suggest("crest browser"), device.Query(Asking(selected, "crest browser")).SuggestionAddress);
    }

    /// What window `window` asks its palette for `text`, completing inline.
    private static PaletteSuggestions Asking(Guid window, string text) =>
        new(window, text, [], [], [], Scope: null, AllowsCompletion: true);
}
