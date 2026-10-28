using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class LinkNavigationDecisionTests {
    [Theory]
    [InlineData(false, false, false, "navigate")]
    [InlineData(true, false, false, "backgroundTab")]
    [InlineData(false, true, false, "foregroundTab")]
    [InlineData(false, false, true, "backgroundTab")]
    [InlineData(true, true, false, "foregroundTab")]
    public void FixedModifiersAndMiddleClickOpenOrdinaryTabs(bool command, bool option, bool middle, string expected) {
        Assert.Equal(LinkNavigationDecision.Named(expected), Decide(placement: null, peek: option, newTab: command || middle));
    }

    [Theory]
    [InlineData("https://www.apple.com/news/", "saved", "navigate")]
    [InlineData("http://APPLE.com:8080/news/", "pinned", "navigate")]
    [InlineData("https://developer.apple.com/", "saved", "foregroundTab")]
    [InlineData("https://example.com/", "pinned", "foregroundTab")]
    [InlineData("https://example.com/", null, "navigate")]
    [InlineData("mailto:test@example.com", "saved", "navigate")]
    [InlineData("file:///tmp/example.html", "saved", "navigate")]
    [InlineData("crest://extensions/", "saved", "navigate")]
    public void SavedSiteProtectionPreservesHostsAndPlacement(string url, string? placement,
        string expected) =>
        Assert.Equal(LinkNavigationDecision.Named(expected), Decide(url, placement: placement));

    [Theory]
    [InlineData(false, "backgroundTab")]
    [InlineData(true, "foregroundTab")]
    public void ExplicitNewTabOverridesSavedSiteAndShiftSelectsIt(bool shift, string expected) =>
        Assert.Equal(LinkNavigationDecision.Named(expected), Decide(newTab: true, shift: shift));

    [Fact]
    public void PreviewModifierOpensANormalTabAndRequiresAnOwnedTopLevelLink() {
        Assert.Equal(LinkNavigationDecision.ForegroundTab, Decide(peek: true, newTab: true));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, topLevel: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, userLink: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide("javascript:alert(1)", peek: true));
    }

    [Fact]
    public void EngineNavigationsAndMissingSavedContextNavigateInPlace() {
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

    private static LinkNavigationDecision Decide(string? url = "https://example.com/", bool userLink = true,
        bool topLevel = true, bool peek = false, bool newTab = false, bool shift = false,
        bool owned = true, string? placement = "saved", string? savedUrl = "https://apple.com/") =>
        LinkNavigationDecision.For(url, userLink, topLevel, peek, newTab, shift, owned, TabPlacement.Named(placement), savedUrl);
}
