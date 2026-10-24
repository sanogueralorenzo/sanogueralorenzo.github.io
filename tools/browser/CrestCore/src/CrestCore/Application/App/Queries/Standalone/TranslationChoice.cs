using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The rule among `Rules` that applies to pages in `SourceLanguage`, whose
/// region aliases share it, and the language such pages are translated into.
/// It reads no state, so a host may ask it without an app.
public sealed record TranslationChoice(IReadOnlyList<TranslationRule> Rules, string SourceLanguage) : StandaloneQuery<TranslationDecision> {
    #region Actions - Answering

    internal override TranslationDecision Answer(StandaloneContext context) {
        var rules = AutomaticTranslationRules.Restore(Rules);
        return new(rules.Rule(SourceLanguage), rules.Target(SourceLanguage));
    }

    #endregion
}
