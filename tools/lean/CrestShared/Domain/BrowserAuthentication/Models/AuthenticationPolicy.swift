import Foundation

enum AuthenticationMethod: String, Sendable {
    case httpBasic, httpDigest, other
}

enum AuthenticationHandling: Sendable {
    case promptForCredentials, performDefaultHandling, cancel

    static func handling(method: AuthenticationMethod, isProxy: Bool, previousFailureCount: Int) -> Self {
        guard !isProxy, method != .other else { return .performDefaultHandling }
        return previousFailureCount < 3 ? .promptForCredentials : .cancel
    }
}

enum AuthenticationSource {
    static func label(host: String, port: Int, scheme: String?, emptyHostLabel: String) -> String {
        guard !host.isEmpty else { return emptyHostLabel }
        return WebScheme.named(scheme?.lowercased())?.defaultPort == port ? host : "\(host):\(port)"
    }
}
