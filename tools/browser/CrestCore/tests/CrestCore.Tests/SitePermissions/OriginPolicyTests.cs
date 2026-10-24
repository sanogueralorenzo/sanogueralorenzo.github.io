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
    public void AnOverlongSchemeIsRefused() =>
        Assert.Equal(ExternalSchemeDisposition.Blocked, UrlScheme.DispositionOf(new string('a', 300), false));

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
    public void LocalDocumentsRefuseRemoteAuthoritiesAndUsers() {
        Assert.True(new LocalDocumentFacts(true, false, true, null).IsAcceptedDocument);
        Assert.True(new LocalDocumentFacts(true, false, true, "LocalHost").IsAcceptedDocument);
        Assert.False(new LocalDocumentFacts(true, false, true, "server").IsAcceptedDocument);
        Assert.False(new LocalDocumentFacts(true, true, true, null).IsAcceptedDocument);
        Assert.False(new LocalDocumentFacts(true, false, false, null).IsAcceptedDocument);
        Assert.False(new LocalDocumentFacts(false, false, true, null).IsAcceptedDocument);
        Assert.False(new LocalDocumentFacts(true, false, true, new string('a', ExternalWebLink.MaximumHostLength + 1)).IsAcceptedDocument);
    }

    [Fact]
    public void NotificationRequestsPromptOnlyWithActivation() {
        Assert.Equal(HostedNotificationRequestAction.PromptForSitePermission, HostedNotificationRequestAction.For(SitePermissionDecision.Ask, true));
        Assert.Equal(HostedNotificationRequestAction.RespondDefault, HostedNotificationRequestAction.For(SitePermissionDecision.Ask, false));
        Assert.Equal(HostedNotificationRequestAction.RespondDenied, HostedNotificationRequestAction.For(SitePermissionDecision.DenyForSession, true));
        Assert.Equal(HostedNotificationRequestAction.ResolveSystemAuthorization,
            HostedNotificationRequestAction.For(SitePermissionDecision.GrantPersistently, false));
    }

    [Fact]
    public void ADocumentShowsOneBlockedPopupIndicationUntilItNavigates() {
        static BlockedPopupPageState? After(BlockedPopupPageState state, BlockedPopupEvent popupEvent, string? document = null,
            SiteOrigin? origin = null) => state.Applying(popupEvent, document, origin);
        var blocked = After(BlockedPopupPageState.Empty, BlockedPopupEvent.Blocked, "doc-1", Site)!;
        Assert.Equal(BlockedPopupStatus.Blocked, blocked.Status);
        Assert.Equal(1, blocked.IndicationRevision);
        Assert.Null(After(blocked, BlockedPopupEvent.Blocked, "doc-1", Site));
        Assert.Null(After(blocked, BlockedPopupEvent.PopupAllowed));

        var allowed = After(blocked, BlockedPopupEvent.PermissionAllowed)!;
        Assert.Equal(BlockedPopupStatus.AllowedAwaitingRetry, allowed.Status);
        Assert.Equal(BlockedPopupStatus.Blocked, After(allowed, BlockedPopupEvent.PermissionBlockedAgain)!.Status);

        var cleared = After(allowed, BlockedPopupEvent.PopupAllowed)!;
        Assert.Null(cleared.Status);
        Assert.Null(cleared.DocumentIdentifier);
        Assert.Equal(1, cleared.IndicationRevision);
        Assert.Null(After(cleared, BlockedPopupEvent.Navigation));
        Assert.Null(After(blocked, BlockedPopupEvent.Navigation)!.Status);
        // An indication needs its document and a readable origin, and a status never stands without its origin.
        Assert.IsType<InvalidBlockedPopup>(Assert.Throws<Rejected>(() => After(cleared, BlockedPopupEvent.Blocked, null, Site)).Rejection);
        Assert.IsType<InvalidBlockedPopup>(Assert.Throws<Rejected>(() =>
            After(cleared, BlockedPopupEvent.Blocked, "doc-2", new SiteOrigin("https", "", 443))).Rejection);
        Assert.IsType<InvalidBlockedPopup>(Assert.Throws<Rejected>(() =>
            After(blocked with { Origin = null }, BlockedPopupEvent.PopupAllowed)).Rejection);
    }

    [Fact]
    public void BasicAndDigestPromptThreeTimesAndProxiesKeepSystemHandling() {
        Assert.Equal(AuthenticationHandling.PromptForCredentials, new ChallengeHandling(AuthenticationMethod.HttpBasic, false, 2).Handling);
        Assert.Equal(AuthenticationHandling.Cancel, new ChallengeHandling(AuthenticationMethod.HttpDigest, false, 3).Handling);
        Assert.Equal(AuthenticationHandling.PerformDefaultHandling, new ChallengeHandling(AuthenticationMethod.HttpBasic, true, 0).Handling);
        Assert.Equal(AuthenticationHandling.PerformDefaultHandling, new ChallengeHandling(AuthenticationMethod.Other, false, 0).Handling);
    }

    [Fact]
    public void TheAuthenticationPromptNamesTheServerWithANonDefaultPort() {
        Assert.Equal("intranet.example", new AuthenticationSource("intranet.example", 443, "HTTPS").Label);
        Assert.Equal("intranet.example:8443", new AuthenticationSource("intranet.example", 8443, "https").Label);
        Assert.Equal("proxy.example:80", new AuthenticationSource("proxy.example", 80, null).Label);
        Assert.Null(new AuthenticationSource("", 443, "https").Label);
    }
}
