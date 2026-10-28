using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Google search addresses encode query text safely.
public sealed class SearchPolicyTests {
    [Theory]
    [InlineData("native mac browser", "native%20mac%20browser")]
    [InlineData("a+b", "a%2Bb")]
    [InlineData("fish & chips=good", "fish%20%26%20chips%3Dgood")]
    [InlineData("C# #tag", "C%23%20%23tag")]
    [InlineData("Café 日本", "Caf%C3%A9%20%E6%97%A5%E6%9C%AC")]
    [InlineData("🦊", "%F0%9F%A6%8A")]
    [InlineData("a/b?c", "a%2Fb%3Fc")]
    [InlineData("-._~", "-._~")]
    [InlineData("%s {searchTerms}", "%25s%20%7BsearchTerms%7D")]
    [InlineData("100%", "100%25")]
    [InlineData("", "")]
    public void QueriesArePercentEncodedOnceAsUtf8IntoTheSinglePlaceholder(string query, string encoded) {
        Assert.Equal("https://www.google.com/search?q=" + encoded, SearchProvider.Google.Search(query));
    }

}
