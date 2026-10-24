import Foundation

/// The platform's page, which shows the person the questions the core asks
/// about it and sends back their answers, whichever engine hosts it. Each
/// question closes once `dismissal` says it no longer waits.
@MainActor
protocol BrowserPromptPresenting: AnyObject {
    /// Shows a script dialog the page's document opened.
    func ask(_ asked: ScriptDialogAsked, dismissal: BrowserPromptDismissal)

    /// Answers a server's request for a user name and password, from the
    /// Space's saved sign-in or by asking the person.
    func ask(_ asked: AuthenticationAsked, dismissal: BrowserPromptDismissal)

    /// Asks the person about a site's request for a capability its Space's
    /// choices do not answer.
    func ask(_ asked: PermissionAsked, dismissal: BrowserPromptDismissal)
}
