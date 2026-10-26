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
    public void EngineNavigationsAndMissingSavedContextNeverBecomeAutomaticPeek() {
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(userLink: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(topLevel: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(savedUrl: null));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(null));
    }

    private static ShortcutModifiers Held(bool command, bool option) =>
        (command ? ShortcutModifiers.Command : ShortcutModifiers.None) | (option ? ShortcutModifiers.Option : ShortcutModifiers.None);

    private static LinkNavigationDecision Decide(string? url = "https://example.com/", bool userLink = true,
        bool topLevel = true, bool peek = false, bool newTab = false, bool shift = false, bool focus = false,
        bool owned = true, string? placement = "saved", string? savedUrl = "https://apple.com/", bool automatic = true) =>
        LinkNavigationDecision.For(url, userLink, topLevel, peek, newTab, shift, focus, owned, TabPlacement.Named(placement), savedUrl,
            automatic);
}
