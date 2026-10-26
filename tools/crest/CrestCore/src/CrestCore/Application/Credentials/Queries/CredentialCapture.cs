using CrestCore.Application;

namespace CrestCore.Contracts;

/// What one credential form observation does to the page's credential state.
/// `Hint` is the page's remembered username from an earlier login step and
/// `Pending` the submitted credential still waiting for a sign-in; neither
/// carries the username or the password. `Now` is in seconds since 1970.
public sealed record CredentialCapture(CredentialFormFacts Facts, CredentialUsernameHint? Hint,
    CredentialPendingCandidate? Pending, double Now) : Query<CredentialCaptureDecision> {
    #region Actions - Answering

    internal override CredentialCaptureDecision Answer(CrestApp app) {
        return Facts.Event.Decide(Facts, Hint, Pending, Now);
    }

    #endregion
}
