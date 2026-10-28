import Foundation

/// The answer to one external-app prompt. Cancelling is deliberately not a
/// remembered block: a person declining one hand-off has not asked Crest to
/// refuse every future one, which Site Permissions is there for. A site's
/// saved choice answers the same way without a prompt: a grant opens, a block
/// cancels.
struct BrowserExternalSchemePromptResponse: Hashable, Sendable {
    // MARK: - Static Variables

    static let open = BrowserExternalSchemePromptResponse(
        name: "open", opens: true, remembers: false, savedVerdict: .grant)
    static let openAndRemember = BrowserExternalSchemePromptResponse(
        name: "openAndRemember", opens: true, remembers: true, savedVerdict: nil)
    static let cancel = BrowserExternalSchemePromptResponse(
        name: "cancel", opens: false, remembers: false, savedVerdict: .deny)
    static let all = [open, openAndRemember, cancel]

    // MARK: - Variables

    let name: String
    /// Whether the hand-off goes ahead.
    let opens: Bool
    /// Whether the site's choice is kept for later hand-offs.
    let remembers: Bool
    /// The site's saved verdict that answers this way without a prompt.
    private let savedVerdict: SitePermissionVerdict?

    // MARK: - Actions - Lookup

    /// The answer a site's saved `verdict` gives without a prompt, or nil when
    /// it leaves the answer to the person.
    static func answering(_ verdict: SitePermissionVerdict) -> BrowserExternalSchemePromptResponse? {
        all.first { $0.savedVerdict == verdict }
    }

    // MARK: - Equatable

    static func == (lhs: BrowserExternalSchemePromptResponse, rhs: BrowserExternalSchemePromptResponse) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
