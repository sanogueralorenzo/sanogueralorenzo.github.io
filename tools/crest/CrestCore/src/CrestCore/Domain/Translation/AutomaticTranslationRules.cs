using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Explicit source-language choices for automatic page translation. Missing,
/// disabled, empty or same-language rules never translate, so no language is
/// translated into the device language by default.
public sealed class AutomaticTranslationRules {
    #region Variables

    public const int MaximumSources = 128;
    public const int MaximumLanguageLength = 64;

    public static AutomaticTranslationRules Empty { get; } = new(new SortedDictionary<string, TranslationRule>(StringComparer.Ordinal));
    /// Every rule, in ordinal order of its source language.
    public IReadOnlyList<TranslationRule> Rules { get; }
    private readonly SortedDictionary<string, TranslationRule> sources;

    #endregion

    #region Constructors

    private AutomaticTranslationRules(SortedDictionary<string, TranslationRule> sources) {
        this.sources = sources;
        Rules = [.. sources.Values];
    }

    #endregion

    #region Actions - Rules

    public static AutomaticTranslationRules Restore(IEnumerable<TranslationRule> stored) {
        ArgumentNullException.ThrowIfNull(stored);
        var values = new SortedDictionary<string, TranslationRule>(StringComparer.Ordinal);
        foreach (var rule in stored) {
            RequireLanguageLength(rule.SourceLanguage, rule.TargetId);
            values[rule.SourceLanguage] = rule;
            if (values.Count > MaximumSources) throw new Rejected(new TranslationRuleLimitReached(MaximumSources));
        }
        return new(values);
    }

    /// The exact rule, else the first region or script alias in ordinal order.
    public TranslationRule? Rule(string source) {
        ArgumentNullException.ThrowIfNull(source);
        if (sources.TryGetValue(source, out var exact)) return exact;
        foreach (var (key, rule) in sources) if (LanguageTag.Matches(key, source)) return rule;
        return null;
    }

    /// The destination to translate a page in `source` into, or null.
    public string? Target(string source) =>
        Rule(source) is { IsEnabled: true } rule && source.Length > 0 && rule.TargetId.Length > 0
            && !LanguageTag.Matches(source, rule.TargetId) ? rule.TargetId : null;

    private static void RequireLanguageLength(string source, string target) {
        if (source.Length > MaximumLanguageLength || target.Length > MaximumLanguageLength)
            throw new Rejected(new LanguageTooLong(MaximumLanguageLength));
    }

    #endregion

    #region Mutators

    /// Records a choice for `source`. Region aliases share one choice, so an
    /// alias cannot bypass disabling; distinct scripts keep separate rules.
    public AutomaticTranslationRules Set(string source, string target, bool isEnabled) {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(target);
        if (source.Length == 0) return this;
        RequireLanguageLength(source, target);
        var values = new SortedDictionary<string, TranslationRule>(StringComparer.Ordinal);
        foreach (var (key, rule) in sources) if (!LanguageTag.Matches(key, source)) values[key] = rule;
        values[source] = new(source, target, isEnabled);
        if (values.Count > MaximumSources) throw new Rejected(new TranslationRuleLimitReached(MaximumSources));
        return new(values);
    }

    #endregion
}
