enum HostedNotificationRequestAction: CaseIterable, CoreNamedValue, Sendable {
    case respondDefault, respondDenied, resolveSystemAuthorization, promptForSitePermission

    var name: String {
        switch self {
        case .respondDefault: "respondDefault"
        case .respondDenied: "respondDenied"
        case .resolveSystemAuthorization: "resolveSystemAuthorization"
        case .promptForSitePermission: "promptForSitePermission"
        }
    }
    static func named(_ name: String?) -> Self? { allCases.first { $0.name == name } }

    static func action(decision: SitePermissionDecision, hasUserActivation: Bool) -> Self {
        switch decision.verdict {
        case .deny: .respondDenied
        case .grant: .resolveSystemAuthorization
        case .ask: hasUserActivation ? .promptForSitePermission : .respondDefault
        }
    }
}
