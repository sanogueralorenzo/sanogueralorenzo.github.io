import Foundation

enum SitePermissionVerdict: Int, CaseIterable, Sendable { case ask, grant, deny }

/// A remembered capability choice; persistent names match the permission document.
struct SitePermissionDecision: Hashable, Sendable {
    static let ask = Self(name: "ask", verdict: .ask, isPersistent: false, precedence: 2, title: "Ask")
    static let grantForSession = Self(
        name: "grantForSession", verdict: .grant, isPersistent: false, precedence: 1, title: "Allowed for Session")
    static let denyForSession = Self(
        name: "denyForSession", verdict: .deny, isPersistent: false, precedence: 3, title: "Blocked for Session")
    static let grantPersistently = Self(
        name: "grantPersistently", verdict: .grant, isPersistent: true, precedence: 0, title: "Allow")
    static let denyPersistently = Self(
        name: "denyPersistently", verdict: .deny, isPersistent: true, precedence: 4, title: "Block")
    static let all = [ask, grantForSession, denyForSession, grantPersistently, denyPersistently]

    let name: String
    let verdict: SitePermissionVerdict
    let isPersistent: Bool
    let precedence: Int
    let title: LocalizedStringResource
    var grants: Bool { verdict == .grant }
    var denies: Bool { verdict == .deny }
    var asks: Bool { verdict == .ask }

    private init(
        name: String, verdict: SitePermissionVerdict, isPersistent: Bool, precedence: Int,
        title: LocalizedStringResource
    ) {
        self.name = name
        self.verdict = verdict
        self.isPersistent = isPersistent
        self.precedence = precedence
        self.title = title
    }
    static func named(_ name: String?) -> Self? { all.first { $0.name == name } }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
