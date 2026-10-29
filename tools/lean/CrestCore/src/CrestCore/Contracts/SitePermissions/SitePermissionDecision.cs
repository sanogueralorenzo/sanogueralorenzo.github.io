namespace CrestCore.Contracts;

/// A person's answer for one capability, origin and Space. Session answers
/// last until the process ends; persistent answers are saved on this device.
///
/// The saved permission document (`crest.site-permissions.v1`) and the
/// permission ledger's JSON spell a decision as its `Name`, so a name never
/// changes.
public sealed class SitePermissionDecision {
    #region Static Variables

    /// Ask clears both the session and the saved choice.
    public static readonly SitePermissionDecision Ask = new(name: "ask", SitePermissionVerdict.Ask, isPersistent: false,
        precedence: 2, title: "Ask");
    public static readonly SitePermissionDecision GrantForSession = new(name: "grantForSession", SitePermissionVerdict.Grant,
        isPersistent: false, precedence: 1, title: "Allowed for Session");
    public static readonly SitePermissionDecision DenyForSession = new(name: "denyForSession", SitePermissionVerdict.Deny,
        isPersistent: false, precedence: 3, title: "Blocked for Session");
    public static readonly SitePermissionDecision GrantPersistently = new(name: "grantPersistently", SitePermissionVerdict.Grant,
        isPersistent: true, precedence: 0, title: "Allow");
    public static readonly SitePermissionDecision DenyPersistently = new(name: "denyPersistently", SitePermissionVerdict.Deny,
        isPersistent: true, precedence: 4, title: "Block");

    public static IReadOnlyList<SitePermissionDecision> All { get; } =
        [Ask, GrantForSession, DenyForSession, GrantPersistently, DenyPersistently];

    #endregion

    #region Variables

    public string Name { get; }

    public SitePermissionVerdict Verdict { get; }

    public bool Grants => Verdict == SitePermissionVerdict.Grant;

    public bool Denies => Verdict == SitePermissionVerdict.Deny;

    /// The decision leaves the question to the person.
    public bool Asks => Verdict == SitePermissionVerdict.Ask;

    /// Only persistent answers are saved; session answers and Ask never are.
    public bool IsPersistent { get; }

    /// When several decisions answer one request together, as a camera and a
    /// microphone answer for combined capture, the one with the highest
    /// precedence holds: any block over no answer, no answer over a session
    /// grant, and a session grant over a saved one.
    public int Precedence { get; }

    /// What the settings call the decision.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SitePermissionDecision(string name, SitePermissionVerdict verdict, bool isPersistent, int precedence, string title) {
        Name = name;
        Verdict = verdict;
        IsPersistent = isPersistent;
        Precedence = precedence;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SitePermissionDecision? Named(string? name) => All.FirstOrDefault(decision => decision.Name == name);

    #endregion

}
