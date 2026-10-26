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
    [Fact]
    public void RetentionExcludesAnExactCutoffAndFutureRecords() {
        // `SweepExpiredRecords` applies this rule.
        Assert.Equal([0], DataRetention.Expired([9, 10, 11, 21], 20, 10));
    }
}
