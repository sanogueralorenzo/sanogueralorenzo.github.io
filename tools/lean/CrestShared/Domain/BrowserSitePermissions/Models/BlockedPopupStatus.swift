import Foundation

enum BlockedPopupStatus: CaseIterable, CoreNamedValue, Sendable {
    case blocked, allowedAwaitingRetry

    var name: String {
        switch self {
        case .blocked: "blocked"
        case .allowedAwaitingRetry: "allowedAwaitingRetry"
        }
    }
    static func named(_ name: String?) -> Self? { allCases.first { $0.name == name } }
    var symbol: String { self == .blocked ? "macwindow.badge.plus" : "checkmark.circle" }
    var offersAllow: Bool { self == .blocked }
    var guidance: LocalizedStringResource {
        switch self {
        case .blocked: "Automatic pop-ups are blocked. Allow them for this site, then retry the action on the page."
        case .allowedAwaitingRetry: "Retry the action on the page. Crest did not reopen the blocked pop-up."
        }
    }
}
