using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Address and retention rules the core applies wherever an address is typed
/// or records expire.
public sealed class BrowsingPolicyTests {
    private static SearchProvider Kagi() =>
        CustomSearchProvider.Carried(Guid.Parse("00000000-0000-0000-0000-000000000264"), "Kagi", "https://kagi.com/search?q=%s", null).Admitted()
            .Provider;

    [Theory]
    [InlineData("apple.com", "https://apple.com", null)]
    [InlineData("localhost:3000", "http://localhost:3000", null)]
    [InlineData("192.168.0.1", "http://192.168.0.1", null)]
    [InlineData("[fe80::1]:8080/setup", "http://[fe80::1]:8080/setup", null)]
    [InlineData("[0:0:0:0:0:0:0:1]:8080", "http://[0:0:0:0:0:0:0:1]:8080", null)]
    [InlineData("printer.local:631", "http://printer.local:631", null)]
    [InlineData("http://192.168.0.1", "http://192.168.0.1", null)]
    [InlineData("https://webkit.org/blog/", "https://webkit.org/blog/", null)]
    [InlineData("  Café + Swift/URL & WebKit  ", "https://kagi.com/search?q=Caf%C3%A9%20%2B%20Swift%2FURL%20%26%20WebKit", "Café + Swift/URL & WebKit")]
    [InlineData("   ", null, null)]
    public void ExistingAddressCallSitesKeepTheirIntentAndURLSpelling(string input, string? url, string? query) {
        var resolved = AddressResolution.Resolve(input, Kagi());
        Assert.Equal(resolved, AddressResolution.Resolve(input, Kagi()));
        Assert.Equal(url, resolved?.Url);
        Assert.Equal(query, resolved?.SearchQuery);
    }
    [Theory]
    [InlineData("chrome://extensions/")]
    [InlineData("crest://extensions/?id=abcdefghijklmnopabcdefghijklmnop#details")]
    [InlineData("CREST://version/")]
    [InlineData("chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html")]
    public void InternalAddressesRequireTheSelectedEngineCapability(string address) {
        var disabled = AddressResolution.Resolve(address, Kagi(), allowsInternalPages: false)!;
        Assert.Equal(address, disabled.SearchQuery);
        var enabled = AddressResolution.Resolve(address, Kagi(), allowsInternalPages: true)!;
        Assert.Equal(address, enabled.Url);
        Assert.Null(enabled.SearchQuery);
    }
    [Fact]
    public void AnAddressCrestHoldsLoadsAsItIsWhereTypedTheSameWordsWouldSearch() {
        string page = "data:text/html;charset=utf-8," + string.Concat(Enumerable.Repeat("%3Cp%3EShowcase%3C%2Fp%3E", 400));
        Assert.Equal(page, AddressResolution.Held(page, allowsInternalPages: false));
        Assert.IsType<UnsupportedAddress>(Assert.Throws<Rejected>(() => AddressResolution.Resolve(page, Kagi())).Rejection);
        Assert.Equal("blob:https://example.com/0f1e", AddressResolution.Held("blob:https://example.com/0f1e", false));
        Assert.Null(AddressResolution.Held("javascript:alert(1)", false));
        Assert.Null(AddressResolution.Held("mailto:crest@example.com", false));
        Assert.Null(AddressResolution.Held("chrome://extensions/", allowsInternalPages: false));
        Assert.Equal("chrome://extensions/", AddressResolution.Held("chrome://extensions/", allowsInternalPages: true));
    }
    [Theory]
    [InlineData("file:///Users/crest/Saved%20Page.webarchive", "file:///Users/crest/Saved%20Page.webarchive")]
    [InlineData("file://localhost/tmp/archive.mhtml", "file:///tmp/archive.mhtml")]
    [InlineData("/tmp/Saved Page.html", "file:///tmp/Saved%20Page.html")]
    [InlineData("file://example.com/tmp/page.html", null)]
    [InlineData("file:", null)]
    public void LocalDocumentAddressesResolveToFileURLsAndRemainValidTabURLs(string input, string? url) {
        var resolved = AddressResolution.Resolve(input, Kagi())!;
        if (url is null) {
            Assert.False(resolved.Url.StartsWith("file:", StringComparison.OrdinalIgnoreCase));
            Assert.IsType<UnsupportedAddress>(Assert.Throws<Rejected>(() => AddressResolution.ValidateUrl(input)).Rejection);
            return;
        }
        Assert.Equal(url, resolved.Url);
        Assert.Null(resolved.SearchQuery);
        AddressResolution.ValidateUrl(url);
    }
    [Fact]
    public void HomeRelativeAddressesResolveAgainstThisDeviceOnly() {
        var resolved = AddressResolution.Resolve("~/Saved.webarchive", Kagi())!;
        Assert.StartsWith("file:///", resolved.Url);
        Assert.EndsWith("/Saved.webarchive", resolved.Url);
        Assert.Null(resolved.SearchQuery);
        Assert.Equal("~notapath", AddressResolution.Resolve("~notapath", Kagi())!.SearchQuery);
    }
    [Fact]
    public void RetentionAndExplicitDeletionKeepTheirDifferentBoundaryRules() {
        // Retention excludes an exact cutoff and future records. Explicit
        // deletion includes its start and excludes its end. The
        // `SweepExpiredRecords` and `RemoveHistoryRange` intents apply this rule.
        Assert.Equal([0], DataRetention.Expired([9, 10, 11, 21], 20, 10));
        Assert.Equal([1, 2], RemoveHistoryRange.WithinRange([9, 10, 11, 20], 10, 20));
        Assert.Empty(RemoveHistoryRange.WithinRange([10], 20, 10));
    }
}
