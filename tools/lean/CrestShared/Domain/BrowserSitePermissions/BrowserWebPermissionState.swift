import Foundation

/// The state a web API tells a document it has for a capability: the
/// Permissions API's spelling, and the Notifications API's for the same
/// state. Each state names the site verdict that alone gives it, if any, and
/// the system answer it reports.
struct BrowserWebPermissionState: Hashable, Sendable {
    // MARK: - Static Variables

    static let granted = BrowserWebPermissionState(
        spelling: "granted", notificationSpelling: "granted", siteVerdict: nil, systemAuthorization: .authorized)
    static let denied = BrowserWebPermissionState(
        spelling: "denied", notificationSpelling: "denied", siteVerdict: .deny, systemAuthorization: .denied)
    static let prompt = BrowserWebPermissionState(
        spelling: "prompt", notificationSpelling: "default", siteVerdict: .ask, systemAuthorization: .notDetermined)
    static let all = [granted, denied, prompt]

    // MARK: - Variables

    /// The Permissions API's spelling.
    let spelling: String
    /// The Notifications API's spelling, as `Notification.permission` gives it.
    let notificationSpelling: String
    /// The site's saved verdict that gives this state on its own; nil for a
    /// grant, which the system's consent still decides.
    private let siteVerdict: SitePermissionVerdict?
    private let systemAuthorization: BrowserSystemAuthorization

    // MARK: - Actions - Lookup

    /// The state a site's saved `verdict` gives on its own, or nil when the
    /// system decides it.
    static func answering(_ verdict: SitePermissionVerdict) -> BrowserWebPermissionState? {
        all.first { $0.siteVerdict == verdict }
    }

    /// The state the system's `authorization` reports.
    static func answering(_ authorization: BrowserSystemAuthorization) -> BrowserWebPermissionState {
        guard let state = all.first(where: { $0.systemAuthorization == authorization }) else {
            preconditionFailure("Every system authorization reports a permission state.")
        }
        return state
    }

    /// Granted when the system `authorizes`, else denied.
    static func granting(_ authorizes: Bool) -> BrowserWebPermissionState {
        authorizes ? .granted : .denied
    }

    // MARK: - Equatable

    static func == (lhs: BrowserWebPermissionState, rhs: BrowserWebPermissionState) -> Bool {
        lhs.spelling == rhs.spelling
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spelling)
    }
}
