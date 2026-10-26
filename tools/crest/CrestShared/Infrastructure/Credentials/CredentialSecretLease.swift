import Foundation

struct BrowserCredentialSecretLease: Sendable {
    static let revealLifetime: TimeInterval = 30
    static let clipboardLifetime: TimeInterval = 60

    private let password: String
    let expiration: Date

    static func reveal(password: String, issuedAt: Date = .now) -> Self {
        Self(
            password: password,
            expiration: issuedAt.addingTimeInterval(revealLifetime)
        )
    }

    static func clipboard(password: String, issuedAt: Date = .now) -> Self {
        Self(
            password: password,
            expiration: issuedAt.addingTimeInterval(clipboardLifetime)
        )
    }

    func password(at date: Date = .now) -> String? {
        date < expiration ? password : nil
    }
}
