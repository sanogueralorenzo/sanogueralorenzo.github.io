using CrestCore.Application;

using Xunit;

namespace CrestCore.Tests;

/// The addresses an import keeps, read exactly as the Apple platforms' URL
/// parser reads them, so a browser-data file either side writes reads back
/// the same on both.
public sealed partial class BrowserContractsTests {
    [Theory]
    // Only http and https addresses with a host are kept.
    [InlineData("ftp://example.com/", null)]
    [InlineData("javascript:alert(1)", null)]
    [InlineData("example.com", null)]
    [InlineData("https:example.com", null)]
    [InlineData("https://", null)]
    [InlineData(" https://example.com", null)]
    // The scheme is lowercased, credentials go, and the rest keeps its case.
    [InlineData("HTTPS://Example.COM/Path", "https://Example.COM/Path")]
    [InlineData("http://user:pass@example.com/a?b=c#d", "http://example.com/a?b=c#d")]
    [InlineData("https://a@b@c.com/", "https://c.com/")]
    [InlineData("https://example.com?x", "https://example.com?x")]
    // A component holding what it cannot is escaped whole, `%` included; a
    // valid one is kept as spelled.
    [InlineData("https://example.com/a b", "https://example.com/a%20b")]
    [InlineData("https://example.com/ä", "https://example.com/%C3%A4")]
    [InlineData("https://example.com/😀", "https://example.com/%F0%9F%98%80")]
    [InlineData("https://example.com/a|b", "https://example.com/a%7Cb")]
    [InlineData("https://example.com/%41", "https://example.com/%41")]
    [InlineData("https://example.com/%zz", "https://example.com/%25zz")]
    [InlineData("https://example.com/a%%41", "https://example.com/a%25%2541")]
    [InlineData("https://example.com/?a=%zz&b=ü", "https://example.com/?a=%25zz&b=%C3%BC")]
    [InlineData("https://example.com/#frag ment", "https://example.com/#frag%20ment")]
    // A host has its escapes undone and is written in its IDNA form; one
    // holding what a host cannot hold is no address.
    [InlineData("https://bücher.de/", "https://xn--bcher-kva.de/")]
    [InlineData("https://BÜCHER.de/x", "https://xn--bcher-kva.de/x")]
    [InlineData("https://例子.测试/", "https://xn--fsqu00a.xn--0zwm56d/")]
    [InlineData("https://ex%41mple.com/", "https://exAmple.com/")]
    [InlineData("https://xn--.com/", null)]
    [InlineData("https://ex ample.com/", null)]
    [InlineData("https://ex<ample.com/", null)]
    [InlineData("https://ex%zzample.com/", null)]
    // A port loses its leading zeros and an empty one is dropped; an IP
    // literal ends its host.
    [InlineData("https://example.com:08080/x", "https://example.com:8080/x")]
    [InlineData("https://example.com:/", "https://example.com/")]
    [InlineData("https://example.com:abc/", null)]
    [InlineData("https://[::1]:8080/a", "https://[::1]:8080/a")]
    [InlineData("https://[::1]x/", null)]
    [InlineData("https://[::1", null)]
    public void AnImportKeepsAnAddressAsTheApplePlatformsReadIt(string source, string? kept) {
        Assert.Equal(kept, ImportAddress.Read(source)?.Spelling);
        // What an import keeps is what a browser-data file may hold.
        if (kept is not null) Assert.True(ImportAddress.TryReadStored(kept, removesFragment: false, out _));
    }

    [Fact]
    public void AnAddressDropsItsFragmentWhereAskedAndNamesItsHostForAnUnnamedTab() {
        Assert.Equal("http://example.com/a?b=c", ImportAddress.Read("http://user:pass@example.com/a?b=c#d", removesFragment: true)?.Spelling);
        Assert.Equal("https://example.com", ImportAddress.Read("https://example.com#x", removesFragment: true)?.Spelling);
        Assert.Equal("fe80::1%en0", ImportAddress.Read("https://[fe80::1%25en0]/")?.Host);
        Assert.Equal("example.com", ImportAddress.Read("https://example.com:8080/x")?.Host);
        Assert.Null(ImportAddress.Read("http://example.com/?" + new string('a', ImportAddress.MaximumLength)));
        // A browser-data file must spell an address as it reads back.
        Assert.False(ImportAddress.TryReadStored("https://example.com/a b", removesFragment: false, out _));
        Assert.False(ImportAddress.TryReadStored("https://example.com:08080/", removesFragment: false, out _));
    }
}
