using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class TranslationRulesTests {
    /// Edits go through the session intent that owns the persisted rules, and
    /// answer the rules as the session stores them.
    private static JsonNode Set(JsonNode rules, string source, string target, bool enabled) {
        var session = new JsonObject {
            ["spaces"] = new JsonArray(),
            ["appPreferences"] = new JsonObject { ["translationRules"] = rules.DeepClone() }
        };
        using var app = new CrestApp();
        var workspace = TestWorkspaces.Open(app, session);
        var authority = app.Workspace(workspace);
        app.Send(new SetTranslationRule(workspace, source, target, enabled));
        return StoredSessionCodec.Encode(authority.Current.AppPreferences!)["translationRules"]!;
    }

    /// What the standalone query answers for `source` over the rules in their
    /// persisted spelling.
    private static TranslationDecision Rule(JsonNode rules, string source) => new StandaloneAnswers().Query(new TranslationChoice(
        [.. rules["sources"]!.AsObject().Select(entry => new TranslationRule(entry.Key, entry.Value!["targetID"]!.GetValue<string>(),
            entry.Value!["isEnabled"]!.GetValue<bool>()))], source));

    private static string? Target(JsonNode rules, string source) => Rule(rules, source).Target;

    private static JsonNode Empty => new JsonObject { ["sources"] = new JsonObject() };

    [Fact]
    public void OnlyExplicitEnabledSourcesTranslateAndRulesKeepTheirPersistedShape() {
        var rules = Empty;
        Assert.Null(Target(rules, "es"));
        rules = Set(rules, "es", "en", true);
        rules = Set(rules, "de", "fr", true);
        rules = Set(rules, "it", "en", false);
        // The persisted native spelling, sorted by source.
        Assert.Equal("{\"sources\":{\"de\":{\"targetID\":\"fr\",\"isEnabled\":true},\"es\":{\"targetID\":\"en\",\"isEnabled\":true},"
            + "\"it\":{\"targetID\":\"en\",\"isEnabled\":false}}}", rules.ToJsonString());
        var stored = JsonNode.Parse("{\"sources\":{\"es\":{\"isEnabled\":true,\"targetID\":\"en\"}}}")!;
        Assert.Equal("en", Target(stored, "es-MX"));
        Assert.Equal("fr", Target(rules, "de"));
        Assert.Null(Target(rules, "it"));
        Assert.Null(Target(rules, "ja"));
        Assert.Equal("en", Rule(rules, "it").Rule!.TargetId);
    }

    [Fact]
    public void ScriptChoicesRemainDistinctAndRegionAliasesCannotBypassDisabling() {
        var rules = Set(Empty, "zh-Hant", "en", true);
        Assert.Equal("en", Target(rules, "zh-TW"));
        Assert.Equal("en", Target(rules, "zh_HK"));
        Assert.Null(Target(rules, "zh-Hans"));
        Assert.Null(Target(rules, "zh"));
        rules = Set(rules, "es", "en", true);
        rules = Set(rules, "es-MX", "fr", false);
        Assert.Null(Target(rules, "es"));
        Assert.Null(Target(rules, "es-ES"));
        Assert.Equal(2, rules["sources"]!.AsObject().Count);
    }

    [Fact]
    public void EmptyOrSameLanguageRulesCannotTriggerAutomaticTranslation() {
        var rules = Set(Empty, "es", "", true);
        Assert.Null(Target(rules, "es"));
        Assert.Null(Target(rules, ""));
        Assert.Equal(Empty.ToJsonString(), Set(Empty, "", "en", true).ToJsonString());
        rules = Set(rules, "en-US", "en-GB", true);
        Assert.Null(Target(rules, "en"));
        rules = Set(rules, "zh-Hans", "zh-Hant", true);
        Assert.Equal("zh-Hant", Target(rules, "zh-Hans"));
        Assert.ThrowsAny<Exception>(() => Rule(JsonNode.Parse("{\"sources\":{\"es\":{\"isEnabled\":true}}}")!, "es"));
    }

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

    [Fact]
    public void RuleSetsAreBounded() {
        var sources = new JsonObject();
        for (int i = 0; i < AutomaticTranslationRules.MaximumSources; i++)
            sources[$"x{(char)('a' + i / 26)}{(char)('a' + i % 26)}"] = new JsonObject { ["targetID"] = "en", ["isEnabled"] = true };
        var full = new JsonObject { ["sources"] = sources };
        Assert.Equal(new LanguageTooLong(AutomaticTranslationRules.MaximumLanguageLength), Assert.Throws<Rejected>(() =>
            AutomaticTranslationRules.Empty.Set(new string('a', 65), "en", true)).Rejection);
        Assert.Equal(new TranslationRuleLimitReached(AutomaticTranslationRules.MaximumSources),
            Assert.Throws<Rejected>(() => Set(full, "ja", "en", true)).Rejection);
    }
}
