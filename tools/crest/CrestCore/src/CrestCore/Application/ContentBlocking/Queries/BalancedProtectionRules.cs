using CrestCore.Application;

namespace CrestCore.Contracts;

/// Crest's bundled Balanced protection, as a content rule list to compile.
public sealed record BalancedProtectionRules() : Query<ContentRuleList> {
    #region Actions - Answering

    internal override ContentRuleList Answer(CrestApp app) {
        return ContentBlockingPolicy.Balanced.RuleList()
            ?? throw new InvalidOperationException("Balanced protection always has a rule list.");
    }

    #endregion
}
