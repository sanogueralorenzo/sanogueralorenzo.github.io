namespace CrestCore.Contracts;

/// Thrown when a rule refuses an intent or a query. The rejection names the rule.
public sealed class Rejected(Rejection rejection) : Exception(rejection.GetType().Name) {
    #region Variables

    public Rejection Rejection { get; } = rejection;

    #endregion
}
