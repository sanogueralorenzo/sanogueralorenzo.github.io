import CoreGraphics
import Foundation

/// Everything the credential fill prompts need from the page layer, and nothing
/// else.
///
/// The two shells reach different pages — one a pooled windowed page, the other
/// the compact shell's resident page — but a fill prompt only ever asks the same
/// four things, and both pages already answer them with identical signatures.
/// They live here as closures rather than behind a protocol, for the same reason
/// `BrowserFindPort`'s do: there is no third implementation to swap in, only two
/// concrete pages, each bound where its shell presents the chrome.
///
/// `spaceID` is carried rather than read back through the app's selection, for
/// the reason `BrowserCredentialPageState` states: a prompt must keep asking the
/// Space its form was submitted in, even after the person has selected another.
///
/// None of the closures carries an isolation annotation, exactly like
/// `BrowserSidebarNavigationPort`'s: annotating them `@MainActor` would also
/// make them `@Sendable`, which the plain function values a View hands over are
/// not. The struct itself is isolated instead.
@MainActor
struct BrowserCredentialFillPort {
    /// The Space this page belongs to — the vault a prompt reads and the
    /// identity it names.
    let spaceID: UUID

    /// How one of the page's CSS pixels maps to a point in this shell — the
    /// page's zoom, and the only thing standing between a rect the page
    /// reported and the place a panel is drawn.
    let contentScale: CGFloat

    /// The page's own icon, where it has loaded one. A prompt shows it beside
    /// the origin it is about, so the site is recognised before it is read.
    let siteIconData: Data?

    /// Puts a saved credential into the form the request came from. Throws
    /// where the form moved on before the fill could land.
    let fill: (BrowserCredential, UUID) async throws -> Void

    /// Puts a freshly generated password into the form and its confirmation
    /// field.
    let fillGeneratedPassword: (String, UUID) async throws -> Void

    /// Closes the prompt without filling anything.
    let dismiss: () -> Void
}
