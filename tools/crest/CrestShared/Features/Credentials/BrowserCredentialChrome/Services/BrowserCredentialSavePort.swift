import Foundation

/// Everything the credential save prompt needs from the page layer, and nothing
/// else.
///
/// Bound the same way `BrowserCredentialFillPort` is, and for the same reason:
/// two concrete pages answer these questions identically, and there is no third
/// implementation a protocol would buy.
///
/// `offerToSystemPasswords` is the one member a shell may leave out. Handing the
/// saved password on to the system's Passwords app needs an API and a
/// presentation anchor only the touch shell has, and its absence is also what
/// keeps the offer out of the prompt: the commit title, the destination line,
/// and the retry action all follow from whether the offer exists.
///
/// None of the closures carries an isolation annotation, exactly like
/// `BrowserSidebarNavigationPort`'s: annotating them `@MainActor` would also
/// make them `@Sendable`, which the plain function values a View hands over are
/// not. The struct itself is isolated instead.
@MainActor
struct BrowserCredentialSavePort {
    /// The Space the submitted form belongs to — the vault the password is
    /// written to and the identity the prompt names.
    let spaceID: UUID

    /// The candidate the page is presenting right now.
    ///
    /// Read back after every await rather than captured, so a prompt only ever
    /// puts away the candidate it was actually about: a second submission can
    /// replace the candidate while the vault is still writing the first.
    let presentedCandidateID: () -> UUID?

    /// Puts the candidate away, whether it was saved, declined, or already held.
    let dismiss: () -> Void

    /// Offers the saved password to the system's Passwords app, under the title
    /// the prompt names it by. `nil` where the shell cannot make that offer.
    let offerToSystemPasswords: SystemPasswordsOffer?

    typealias SystemPasswordsOffer =
        (BrowserCredentialSaveCandidate, String) async throws -> Void
}
