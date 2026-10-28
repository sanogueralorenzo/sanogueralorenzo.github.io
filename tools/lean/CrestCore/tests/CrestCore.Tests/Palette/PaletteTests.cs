using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What a window's palette reveals and sends away: remote suggestions require
/// a device-wide opt-in and never leave a private window.
public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("persistent", false, false)]
    [InlineData("persistent", true, true)]
    [InlineData("private", false, false)]
    [InlineData("private", true, false)]
    public void SearchSuggestionsAreOptInAndNeverLeavePrivateWindows(string kind, bool enabled, bool asks) {
        var (document, space, _) = SavedSession();
        var session = document["session"]!;
        using var device = new TestDevice(session);
        var workspace = kind == "private" ? device.Attach(session.DeepClone(), WorkspaceKind.Private) : device.Workspace;
        var window = device.OpenIn(workspace, space);
        Assert.Null(device.Query(Asking(window, "crest browser")).SuggestionAddress);
        device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { SearchSuggestionsEnabled = enabled }));

        var answer = device.Query(Asking(window, "crest browser"));

        Assert.Equal(asks, answer.SuggestionAddress is not null);
        Assert.Null(device.Query(Asking(window, "   ")).SuggestionAddress);
        // Disabling suggestions also rejects stale results already fetched by the host.
        var merged = device.Query(Asking(window, "crest browser") with { Remote = ["crest browser download", "Crest Browser"] });
        var suggestions = merged.Groups.Where(group => group.Section == PaletteSection.SearchSuggestions)
            .SelectMany(group => group.Rows).Select(row => row.Title);
        Assert.Equal(asks ? ["crest browser download"] : [], suggestions);
        device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default));
        Assert.Null(device.Query(Asking(window, "crest browser")).SuggestionAddress);
        Assert.DoesNotContain(device.Query(Asking(window, "crest browser") with { Remote = ["stale result"] }).Groups,
            group => group.Section == PaletteSection.SearchSuggestions);
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
        device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { SearchProvider = provider, SearchSuggestionsEnabled = true }));
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
        device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { SearchProvider = SearchProvider.Bing, SearchSuggestionsEnabled = true }));
        Assert.Equal(SearchProvider.Bing.Suggest("crest browser"), device.Query(Asking(selected, "crest browser")).SuggestionAddress);
    }

    /// What window `window` asks its palette for `text`, completing inline.
    private static PaletteSuggestions Asking(Guid window, string text) =>
        new(window, text, [], [], [], Scope: null, AllowsCompletion: true);
}
