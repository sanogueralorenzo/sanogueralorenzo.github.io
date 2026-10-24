namespace CrestCore.Contracts;

/// What a page's `Notification.requestPermission()` call leads to. Each action
/// answers one verdict of the site's saved decision: a request prompts only
/// with user activation, a saved block answers denied, and a grant still needs
/// the system's consent.
public sealed class HostedNotificationRequestAction {
    #region Types

    /// Each platform answers the page with its own code, so the one place that
    /// answers switches over the kind.
    public enum Kinds { RespondDefault, RespondDenied, ResolveSystemAuthorization, PromptForSitePermission }

    #endregion

    #region Variables

    public static readonly HostedNotificationRequestAction RespondDefault = new(Kinds.RespondDefault, name: "respondDefault",
        answers: SitePermissionVerdict.Ask, answersUserActivation: false);
    public static readonly HostedNotificationRequestAction RespondDenied = new(Kinds.RespondDenied, name: "respondDenied",
        answers: SitePermissionVerdict.Deny, answersUserActivation: null);
    public static readonly HostedNotificationRequestAction ResolveSystemAuthorization = new(Kinds.ResolveSystemAuthorization,
        name: "resolveSystemAuthorization", answers: SitePermissionVerdict.Grant, answersUserActivation: null);
    public static readonly HostedNotificationRequestAction PromptForSitePermission = new(Kinds.PromptForSitePermission,
        name: "promptForSitePermission", answers: SitePermissionVerdict.Ask, answersUserActivation: true);

    public static IReadOnlyList<HostedNotificationRequestAction> All { get; } =
        [RespondDefault, RespondDenied, ResolveSystemAuthorization, PromptForSitePermission];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The verdict of the saved decision this action answers.
    public SitePermissionVerdict Answers { get; }

    /// Whether the action answers only a request with, or without, user
    /// activation; null when it answers either.
    public bool? AnswersUserActivation { get; }

    #endregion

    #region Constructors

    private HostedNotificationRequestAction(Kinds kind, string name, SitePermissionVerdict answers, bool? answersUserActivation) {
        Kind = kind;
        Name = name;
        Answers = answers;
        AnswersUserActivation = answersUserActivation;
    }

    #endregion

    #region Actions - Lookup

    public static HostedNotificationRequestAction? Named(string? name) => All.FirstOrDefault(action => action.Name == name);

    /// What a request leads to under the site's saved `decision`.
    public static HostedNotificationRequestAction For(SitePermissionDecision decision, bool hasUserActivation) {
        ArgumentNullException.ThrowIfNull(decision);
        return All.First(action => action.Answers == decision.Verdict
            && (action.AnswersUserActivation ?? hasUserActivation) == hasUserActivation);
    }

    #endregion
}
