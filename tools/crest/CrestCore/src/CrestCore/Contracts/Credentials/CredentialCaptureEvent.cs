namespace CrestCore.Contracts;

/// A credential form observation, or `Filled` when the native layer finished
/// filling a saved credential into the page. Each event decides what it means
/// for the page's credential state: credentials are only captured and offered
/// where both the frame and its top-level page are secure. An event travels as
/// its index in `All`, so `All` is append-only.
public sealed class CredentialCaptureEvent {
    #region Static Variables

    public static readonly CredentialCaptureEvent Username = new(name: "username", decide: RememberUsername);
    public static readonly CredentialCaptureEvent Focus = new(name: "focus", decide: (facts, accepted, hint, _, now) => {
        if (facts.PasswordKind is null) return CredentialCaptureDecision.For(CredentialCaptureAction.DismissFill);
        if (!accepted || !facts.HasFormId || !facts.HasFillTarget) return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        var source = UsernameSource(facts, hint, now);
        return CredentialCaptureDecision.For(CredentialCaptureAction.OfferFill, source, source == CredentialUsernameSource.None,
            facts.FrameOrigin != facts.TopLevelOrigin, facts.IsMainFrame);
    });
    public static readonly CredentialCaptureEvent Submit = new(name: "submit", decide: (facts, accepted, hint, _, now) => {
        if (!accepted) return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        var source = UsernameSource(facts, hint, now);
        if (source == CredentialUsernameSource.None)
            return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore, clearsUsernameHint: true);
        if (!facts.HasPassword || facts.PasswordKind is null) return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        return CredentialCaptureDecision.For(CredentialCaptureAction.CaptureCandidate, source,
            isCrossOriginFrame: facts.FrameOrigin != facts.TopLevelOrigin);
    });
    public static readonly CredentialCaptureEvent DocumentState = new(name: "documentState", decide: (facts, _, _, pending, now) => {
        if (pending is null || facts.HasVisiblePasswordField is not { } visible
            || !facts.IsMainFrame && facts.FrameOrigin != pending.Origin.Validated())
            return CredentialCaptureDecision.For(CredentialCaptureAction.Ignore);
        if (pending.OffersSave(visible, now))
            return CredentialCaptureDecision.For(CredentialCaptureAction.OfferSave);
        return CredentialCaptureDecision.For(
            pending.Age(now) > CredentialPendingCandidate.Lifetime
                ? CredentialCaptureAction.DiscardPending : CredentialCaptureAction.KeepPending);
    });
    public static readonly CredentialCaptureEvent Filled = new(name: "filled", decide: RememberUsername);

    public static IReadOnlyList<CredentialCaptureEvent> All { get; } = [Username, Focus, Submit, DocumentState, Filled];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the observation means, given its facts, whether its frame and
    /// top-level page are secure, the page's remembered username, its pending
    /// candidate and the time now.
    private readonly Func<CredentialFormFacts, bool, CredentialUsernameHint?, CredentialPendingCandidate?, double,
        CredentialCaptureDecision> decide;

    #endregion

    #region Constructors

    private CredentialCaptureEvent(string name,
        Func<CredentialFormFacts, bool, CredentialUsernameHint?, CredentialPendingCandidate?, double, CredentialCaptureDecision> decide) {
        Name = name;
        this.decide = decide;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialCaptureEvent? Named(string? name) => All.FirstOrDefault(captureEvent => captureEvent.Name == name);

    #endregion

    #region Actions - Capture

    /// What the observation `facts` of this event does to the page's credential
    /// state, given its remembered username `hint` and its `pending` candidate.
    public CredentialCaptureDecision Decide(CredentialFormFacts facts, CredentialUsernameHint? hint, CredentialPendingCandidate? pending,
        double now) {
        ArgumentNullException.ThrowIfNull(facts);
        bool accepted = facts.FrameOrigin.IsSecureUnder(facts.TopLevelOrigin);
        return decide(facts, accepted, hint, pending, now);
    }

    private static CredentialCaptureDecision RememberUsername(CredentialFormFacts facts, bool accepted, CredentialUsernameHint? hint,
        CredentialPendingCandidate? pending, double now) =>
        CredentialCaptureDecision.For(accepted && facts.HasUsername ? CredentialCaptureAction.RememberUsername : CredentialCaptureAction.Ignore);

    /// An explicit username wins; otherwise a remembered one that still applies.
    private static CredentialUsernameSource UsernameSource(CredentialFormFacts facts, CredentialUsernameHint? hint, double now) {
        if (facts.HasUsername) return CredentialUsernameSource.Explicit;
        return hint is not null && hint.Applies(facts.FrameOrigin, facts.TopLevelOrigin, now)
            ? CredentialUsernameSource.Hint : CredentialUsernameSource.None;
    }

    #endregion
}
