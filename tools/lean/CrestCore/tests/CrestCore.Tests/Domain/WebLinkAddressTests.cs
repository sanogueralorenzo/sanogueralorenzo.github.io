using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class WebLinkAddressTests {
    [Fact]
    public void WebLinksNeedHttpOrHttpsAndAHost() {
        Assert.True(new WebLinkAddress("HTTPS", "example.com").IsAccepted);
        Assert.True(new WebLinkAddress("http", "example.com").IsAccepted);
        Assert.False(new WebLinkAddress("https", "").IsAccepted);
        Assert.False(new WebLinkAddress("file", null).IsAccepted);
        Assert.False(new WebLinkAddress("javascript", "example.com").IsAccepted);
        Assert.False(new WebLinkAddress(null, "example.com").IsAccepted);
        Assert.False(new WebLinkAddress("https", new string('a', WebLinkAddress.MaximumHostLength + 1)).IsAccepted);
    }
}
