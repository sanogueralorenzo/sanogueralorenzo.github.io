using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Address and retention rules the core applies wherever an address is typed
/// or records expire.
public sealed class BrowsingPolicyTests {
    [Theory]
    [InlineData("apple.com", "https://apple.com", null)]
    [InlineData("localhost:3000", "http://localhost:3000", null)]
    [InlineData("192.168.0.1", "http://192.168.0.1", null)]
    [InlineData("[fe80::1]:8080/setup", "http://[fe80::1]:8080/setup", null)]
    [InlineData("[0:0:0:0:0:0:0:1]:8080", "http://[0:0:0:0:0:0:0:1]:8080", null)]
    [InlineData("printer.local:631", "http://printer.local:631", null)]
    [InlineData("http://192.168.0.1", "http://192.168.0.1", null)]
    [InlineData("https://webkit.org/blog/", "https://webkit.org/blog/", null)]
    [InlineData("  Café + Swift/URL & WebKit  ", "https://www.google.com/search?q=Caf%C3%A9%20%2B%20Swift%2FURL%20%26%20WebKit", "Café + Swift/URL & WebKit")]
    [InlineData("   ", null, null)]
    public void ExistingAddressCallSitesKeepTheirIntentAndURLSpelling(string input, string? url, string? query) {
        var resolved = AddressResolution.Resolve(input, SearchProvider.Google);
        Assert.Equal(resolved, AddressResolution.Resolve(input, SearchProvider.Google));
        Assert.Equal(url, resolved?.Url);
        Assert.Equal(query, resolved?.SearchQuery);
    }
    [Theory]
    [InlineData("chrome://extensions/")]
    [InlineData("crest://extensions/?id=abcdefghijklmnopabcdefghijklmnop#details")]
    [InlineData("CREST://version/")]
    [InlineData("chrome-extension://abcdefghijklmnopabcdefghijklmnop/options.html")]
    public void InternalAddressesRequireTheSelectedEngineCapability(string address) {
        var disabled = AddressResolution.Resolve(address, SearchProvider.Google, allowsInternalPages: false)!;
        Assert.Equal(address, disabled.SearchQuery);
        var enabled = AddressResolution.Resolve(address, SearchProvider.Google, allowsInternalPages: true)!;
        Assert.Equal(address, enabled.Url);
        Assert.Null(enabled.SearchQuery);
    }
    [Fact]
    public void OversizedTypedInputIsRefused() {
        string page = "data:text/html;charset=utf-8," + string.Concat(Enumerable.Repeat("%3Cp%3EShowcase%3C%2Fp%3E", 400));
        Assert.IsType<UnsupportedAddress>(Assert.Throws<Rejected>(() => AddressResolution.Resolve(page, SearchProvider.Google)).Rejection);
    }
    [Theory]
    [InlineData("file:///Users/crest/Saved%20Page.webarchive", "file:///Users/crest/Saved%20Page.webarchive")]
    [InlineData("file://localhost/tmp/archive.mhtml", "file:///tmp/archive.mhtml")]
    [InlineData("/tmp/Saved Page.html", "file:///tmp/Saved%20Page.html")]
    [InlineData("file://example.com/tmp/page.html", null)]
    [InlineData("file:", null)]
    public void LocalDocumentAddressesResolveToFileURLsAndRemainValidTabURLs(string input, string? url) {
        var resolved = AddressResolution.Resolve(input, SearchProvider.Google)!;
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
        var resolved = AddressResolution.Resolve("~/Saved.webarchive", SearchProvider.Google)!;
        Assert.StartsWith("file:///", resolved.Url);
        Assert.EndsWith("/Saved.webarchive", resolved.Url);
        Assert.Null(resolved.SearchQuery);
        Assert.Equal("~notapath", AddressResolution.Resolve("~notapath", SearchProvider.Google)!.SearchQuery);
    }
    [Fact]
    public void RetentionAndExplicitDeletionKeepTheirDifferentBoundaryRules() {
        // Retention excludes an exact cutoff and future records. Explicit
        // deletion includes its start and excludes its end. The
        // `SweepExpiredRecords` and `RemoveHistoryRange` intents apply this rule.
        Assert.Equal([0], DataRetention.Expired([9, 10, 11, 21], 20, 10));
    }
}
