using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class LanguageTagTests {
    [Theory]
    [InlineData("en", "en-GB", true)]
    [InlineData("EN_us", "en-Latn", true)]
    [InlineData("zh-TW", "zh-Hant", true)]
    [InlineData("zh-Hant-CN", "zh-TW", true)]
    [InlineData("zh-CN", "zh-TW", false)]
    [InlineData("sr", "sr-Latn", false)]
    [InlineData("sr-ME", "sr-Latn", true)]
    [InlineData("pa-PK", "pa", false)]
    [InlineData("pt-BR", "pt-PT", true)]
    [InlineData("xx", "xx-YY", true)]
    [InlineData("es", "en", false)]
    [InlineData("", "", false)]
    [InlineData("123", "123", false)]
    public void LanguagesMatchByLanguageAndEffectiveScript(string left, string right, bool matches) {
        Assert.Equal(matches, LanguageTag.Matches(left, right));
        var batch = new StandaloneAnswers().Query(new LanguagesMatching(left, [right, "ja"]));
        Assert.Equal([matches, false], batch.Matches);
    }

}
