import Foundation

// MARK: - Types

/// How to read, ask for and recover the system's answer about one
/// capability, such as the person's location or notifications.
struct BrowserSystemAuthorizationAccess {
    /// The system's answer now.
    let current: @MainActor () async -> BrowserSystemAuthorization
    /// Asks the person; nil when the caller may not ask.
    let request: (@MainActor () async -> BrowserSystemAuthorization)?
    /// Offers the person a way to undo a refusal, such as System Settings.
    let recover: @MainActor () async -> Void
}

/// Whether the system lets Crest use something the person allows in System
/// Settings, such as their location or notifications. Each answer carries how
/// Crest goes on from it: an allowed one authorizes, an undecided one asks the
/// person, and a refused one offers to recover.
struct BrowserSystemAuthorization: Hashable, Sendable {
    // MARK: - Static Variables

    static let notDetermined = BrowserSystemAuthorization(name: "notDetermined") { access in
        guard let request = access.request else { return false }
        return await request() == .authorized
    }
    static let denied = BrowserSystemAuthorization(name: "denied") { access in
        await access.recover()
        return await access.current() == .authorized
    }
    static let authorized = BrowserSystemAuthorization(name: "authorized") { _ in true }

    // MARK: - Variables

    let name: String
    private let settles: @MainActor @Sendable (BrowserSystemAuthorizationAccess) async -> Bool

    // MARK: - Initializers

    private init(
        name: String, settles: @escaping @MainActor @Sendable (BrowserSystemAuthorizationAccess) async -> Bool
    ) {
        self.name = name
        self.settles = settles
    }

    // MARK: - Actions - Authorizing

    /// Whether the system lets Crest go on, starting from this answer and
    /// asking or recovering through `access` as it needs.
    @MainActor func authorizes(through access: BrowserSystemAuthorizationAccess) async -> Bool {
        await settles(access)
    }

    // MARK: - Equatable

    static func == (lhs: BrowserSystemAuthorization, rhs: BrowserSystemAuthorization) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
