using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class LinkNavigationDecisionTests {
    [Theory]
    [InlineData(true, false, false, "option", "backgroundTab")]
    [InlineData(false, true, false, "option", "peekModifier")]
    [InlineData(true, false, false, "command", "peekModifier")]
    [InlineData(false, true, false, "command", "backgroundTab")]
    [InlineData(true, true, false, "option", "peekModifier")]
    [InlineData(true, true, false, "command", "peekModifier")]
    [InlineData(false, false, true, "option", "backgroundTab")]
    [InlineData(false, false, true, "command", "backgroundTab")]
    [InlineData(false, true, true, "option", "peekModifier")]
    public void ConfigurableModifiersAndMiddleClickUseOneNavigationPolicy(bool command, bool option, bool middle,
        string preferenceName, string expectedName) {
        var expected = LinkNavigationDecision.Named(expectedName)!;
        var (peek, newTab) = LinkPeekModifier.Named(preferenceName)!.Intent(Held(command, option), middle);
        Assert.Equal(expected, Decide(peek: peek, newTab: newTab));
        Assert.Equal(expected == LinkNavigationDecision.BackgroundTab ? LinkNavigationDecision.ForegroundTab : expected,
            Decide(peek: peek, newTab: newTab, shift: true));
    }

    [Fact]
    public void HoldingBothKeysDoesNotTurnDeclinedPeekIntoANewTab() {
        var (peek, newTab) = LinkPeekModifier.Option.Intent(Held(true, true), false);
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: peek, newTab: newTab, owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: peek, newTab: newTab, topLevel: false));
    }

    [Theory]
    [InlineData("https://www.apple.com/news/", "saved", true, "navigate")]
    [InlineData("http://APPLE.com:8080/news/", "pinned", true, "navigate")]
    [InlineData("https://developer.apple.com/", "saved", true, "peekSavedSite")]
    [InlineData("https://example.com/", "pinned", true, "peekSavedSite")]
    [InlineData("https://example.com/", null, true, "navigate")]
    [InlineData("https://example.com/", "saved", false, "navigate")]
    [InlineData("mailto:test@example.com", "saved", true, "navigate")]
    [InlineData("file:///tmp/example.html", "saved", true, "navigate")]
    [InlineData("crest://extensions/", "saved", true, "navigate")]
    public void SavedSiteProtectionPreservesHostsPlacementAndOptOut(string url, string? placement,
        bool automaticallyOpensPeek, string expected) =>
        Assert.Equal(LinkNavigationDecision.Named(expected), Decide(url, placement: placement, automatic: automaticallyOpensPeek));

    [Theory]
    [InlineData(false, false, "backgroundTab")]
    [InlineData(false, true, "foregroundTab")]
    [InlineData(true, false, "foregroundTab")]
    [InlineData(true, true, "backgroundTab")]
    public void ExplicitNewTabOverridesSavedSiteAndShiftReversesSelection(bool focus, bool shift, string expected) =>
        Assert.Equal(LinkNavigationDecision.Named(expected), Decide(newTab: true, shift: shift, focus: focus));

    [Fact]
    public void PeekModifierWinsOverNewTabButRequiresAnOwnedTopLevelLink() {
        Assert.Equal(LinkNavigationDecision.PeekModifier, Decide(peek: true, newTab: true));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, topLevel: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, userLink: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide("javascript:alert(1)", peek: true));
    }

    [Fact]
    public void EngineNavigationsAndMissingSavedContextNeverBecomeAutomaticPeek() {
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(userLink: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(topLevel: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(savedUrl: null));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(null));
    }

    [Fact]
    public void InternationalHostSpellingsDoNotSplitTheSavedSite() =>
        Assert.Equal(LinkNavigationDecision.Navigate, Decide("https://www.xn--bcher-kva.example/page",
            savedUrl: "https://bücher.example/"));

    private static ShortcutModifiers Held(bool command, bool option) =>
        (command ? ShortcutModifiers.Command : ShortcutModifiers.None) | (option ? ShortcutModifiers.Option : ShortcutModifiers.None);

    private static LinkNavigationDecision Decide(string? url = "https://example.com/", bool userLink = true,
        bool topLevel = true, bool peek = false, bool newTab = false, bool shift = false, bool focus = false,
        bool owned = true, string? placement = "saved", string? savedUrl = "https://apple.com/", bool automatic = true) =>
        LinkNavigationDecision.For(url, userLink, topLevel, peek, newTab, shift, focus, owned, TabPlacement.Named(placement), savedUrl,
            automatic);
}
