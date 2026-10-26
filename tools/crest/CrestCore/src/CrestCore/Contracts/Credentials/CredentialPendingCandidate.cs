namespace CrestCore.Contracts;

/// A submitted credential still waiting for the page to show it signed in.
/// `SubmittedAt` is in seconds since 1970.
public sealed record CredentialPendingCandidate(CredentialOrigin Origin, double SubmittedAt) {
    #region Static Variables

    /// Seconds a submitted credential waits for the page to show it signed in.
    internal const double Lifetime = 45;

    #endregion

    #region Actions - Capture

    /// Seconds since the candidate was submitted at `now`.
    internal double Age(double now) => Seconds(now) - Seconds(SubmittedAt);

    /// A candidate is current from its submission until its lifetime ends. A
    /// candidate from the future is never current.
    internal bool IsCurrent(double now) => Age(now) is >= 0 and <= Lifetime;

    /// Whether the page now shows it signed in: the candidate is current and
    /// no password field is visible.
    internal bool OffersSave(bool hasVisiblePasswordField, double now) => IsCurrent(now) && !hasVisiblePasswordField;

    /// Whether the candidate, from a frame under a top-level page at
    /// `topLevelOrigin`, may still be planned or committed at `now`.
    internal CredentialSaveValidity SaveValidity(CredentialOrigin topLevelOrigin, double now) {
        if (!Origin.IsSecureUnder(topLevelOrigin)) return CredentialSaveValidity.InsecureOrigin;
        return IsCurrent(now) ? CredentialSaveValidity.Accepted : CredentialSaveValidity.Stale;
    }

    /// `value`, or the refusal of a date or clock reading that is not finite.
    internal static double Seconds(double value) =>
        double.IsFinite(value) ? value : throw new Rejected(new InvalidCredentialDate());

    #endregion
}
