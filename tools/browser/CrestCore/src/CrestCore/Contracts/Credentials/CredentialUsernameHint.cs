namespace CrestCore.Contracts;

/// The page's remembered username from an earlier step of a multi-step login,
/// without the username itself. `CapturedAt` is in seconds since 1970.
public sealed record CredentialUsernameHint(CredentialOrigin Origin, CredentialOrigin TopLevelOrigin, double CapturedAt) {
    #region Static Variables

    /// Seconds a username from one login step is kept for the next step.
    internal const double Lifetime = 5 * 60;

    #endregion

    #region Actions - Capture

    /// A remembered username applies only to the exact frame and top-level
    /// origins that produced it, and only within its lifetime.
    internal bool Applies(CredentialOrigin frameOrigin, CredentialOrigin topLevelOrigin, double now) =>
        Origin.Validated() == frameOrigin && TopLevelOrigin.Validated() == topLevelOrigin
        && CredentialPendingCandidate.Seconds(now) - CredentialPendingCandidate.Seconds(CapturedAt) <= Lifetime;

    #endregion
}
