using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What a window's palette reveals and sends away: it asks a search engine for
/// suggestions only where the person turned them on and never in a private
/// window, and over a locked Space it offers none of the Space's tabs or
/// history.
public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("persistent", true, true)]
    [InlineData("persistent", false, false)]
    [InlineData("private", true, false)]
    public void APaletteAsksForSearchSuggestionsOnlyWhereThePersonAllowsThemAndNeverInAPrivateWindow(string kind, bool enabled,
        bool asks) {
        var (document, space, _) = SavedSession();
        var session = document["session"]!;
        session["spaces"]![0]!["browsingPreferences"]!["searchSuggestionsEnabled"] = enabled;
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

    [Fact]
    public void APaletteOverALockedSpaceOffersNoneOfItsTabsOrHistory() {
        var session = GuardedSession();
        var identity = Identity(session);
        using var device = new TestDevice(session);
        var window = device.Open(identity.Space);
        PaletteAnswer Asked(string text) => device.Query(Asking(window, text));

        foreach (var text in new[] { "", "reading", "earlier", "example.co" }) {
            var locked = Asked(text);
            Assert.All(locked.Groups, group => Assert.Contains(group.Section, new[] { PaletteSection.Intent, PaletteSection.Actions }));
            Assert.Null(locked.Completion);
            Assert.Null(locked.SuggestionAddress);
        }

        Unlock(device.Send, device.Workspace, identity.Space);
        Assert.Contains(Asked("reading").Groups, group => group.Section == PaletteSection.Saved);
        Assert.NotNull(Asked("example.co").Completion);
    }

    /// What window `window` asks its palette for `text`, completing inline.
    private static PaletteSuggestions Asking(Guid window, string text) =>
        new(window, text, [], [], [], Provider: null, Scope: null, AllowsCompletion: true, Pasteboard: null);
}
