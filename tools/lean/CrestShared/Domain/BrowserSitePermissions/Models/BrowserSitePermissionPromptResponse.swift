/// How the person answered a site's permission prompt: whether the request
/// goes ahead, and the decision saved for the site's later requests, if any.
/// Dismissing the prompt answers `denyOnce`, so it never saves a denial.
struct BrowserSitePermissionPromptResponse: Hashable, Sendable {
    // MARK: - Variables

    static let allowOnce = BrowserSitePermissionPromptResponse(name: "allowOnce", grants: true, savedDecision: nil)
    static let denyOnce = BrowserSitePermissionPromptResponse(name: "denyOnce", grants: false, savedDecision: nil)
    static let grantPersistently = BrowserSitePermissionPromptResponse(
        name: "grantPersistently", grants: true, savedDecision: .grantPersistently)
    static let denyPersistently = BrowserSitePermissionPromptResponse(
        name: "denyPersistently", grants: false, savedDecision: .denyPersistently)

    let name: String

    /// Whether the request that prompted goes ahead.
    let grants: Bool

    /// The decision remembered for the site, or nil when the answer covers
    /// only this request.
    let savedDecision: SitePermissionDecision?

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSitePermissionPromptResponse, rhs: BrowserSitePermissionPromptResponse) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
