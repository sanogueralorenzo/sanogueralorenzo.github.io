using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class OriginPolicyTests {
    private static readonly SiteOrigin Site = new("https", "site.example", 443);

    [Theory]
    [InlineData("https", "maps.example", true)]
    [InlineData("http", "localhost", true)]
    [InlineData("http", "127.0.0.1", true)]
    [InlineData("http", "::1", true)]
    [InlineData("http", "maps.example", false)]
    [InlineData("file", "localhost", false)]
    [InlineData("https", "", false)]
    public void PowerfulFeaturesNeedASecureContext(string scheme, string host, bool allowed) =>
        Assert.Equal(allowed, new SiteOrigin(scheme, host, 0).IsSecureContext);

    [Theory]
    [InlineData("https", false, "engine")]
    [InlineData("DATA", false, "engine")]
    [InlineData("blob", false, "engine")]
    [InlineData("javascript", true, "blocked")]
    [InlineData("file", false, "blocked")]
    [InlineData("file", true, "engine")]
    [InlineData("mailto", false, "handOff")]
    [InlineData("zoommtg", false, "handOff")]
    [InlineData(null, false, "engine")]
    public void SchemesAreKeptBlockedOrHandedOff(string? scheme, bool appInitiated, string expected) =>
        Assert.Equal(expected, UrlScheme.DispositionOf(scheme, appInitiated).Name);

    [Fact]
    public void WebLinksNeedHttpOrHttpsAndAHost() {
        Assert.True(new ExternalWebLink("HTTPS", "example.com").IsAccepted);
        Assert.True(new ExternalWebLink("http", "example.com").IsAccepted);
        Assert.False(new ExternalWebLink("https", "").IsAccepted);
        Assert.False(new ExternalWebLink("file", null).IsAccepted);
        Assert.False(new ExternalWebLink("javascript", "example.com").IsAccepted);
        Assert.False(new ExternalWebLink(null, "example.com").IsAccepted);
        Assert.False(new ExternalWebLink("https", new string('a', ExternalWebLink.MaximumHostLength + 1)).IsAccepted);
    }

    [Fact]
    public void BasicAndDigestPromptThreeTimesAndProxiesKeepSystemHandling() {
        Assert.Equal(AuthenticationHandling.PromptForCredentials, new ChallengeHandling(AuthenticationMethod.HttpBasic, false, 2).Handling);
        Assert.Equal(AuthenticationHandling.Cancel, new ChallengeHandling(AuthenticationMethod.HttpDigest, false, 3).Handling);
        Assert.Equal(AuthenticationHandling.PerformDefaultHandling, new ChallengeHandling(AuthenticationMethod.HttpBasic, true, 0).Handling);
        Assert.Equal(AuthenticationHandling.PerformDefaultHandling, new ChallengeHandling(AuthenticationMethod.Other, false, 0).Handling);
    }
}
