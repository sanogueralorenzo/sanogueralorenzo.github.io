namespace CrestCore.Domain;

/// Something broke `Rule`.
public sealed class BrowserRuleException(BrowserRule rule) : Exception(rule.Code) {
    #region Variables

    public BrowserRule Rule { get; } = rule;

    #endregion
}
