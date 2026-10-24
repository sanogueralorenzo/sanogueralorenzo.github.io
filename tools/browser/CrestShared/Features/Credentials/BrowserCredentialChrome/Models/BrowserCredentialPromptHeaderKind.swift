import Foundation

/// Which fill prompt a header opens.
struct BrowserCredentialPromptHeaderKind: Hashable, Sendable {
    // MARK: - Static Variables

    static let strongPassword = BrowserCredentialPromptHeaderKind(
        name: "strongPassword", symbol: "key.horizontal.fill", title: { "Strong Password for \($0)" })
    static let suggestions = BrowserCredentialPromptHeaderKind(
        name: "suggestions", symbol: "key.fill", title: { "Passwords in \($0)" })

    // MARK: - Variables

    let name: String
    let symbol: String

    /// The header's title for the Space the prompt fills from.
    let title: @Sendable (_ spaceName: String) -> LocalizedStringResource

    // MARK: - Initializers

    private init(
        name: String, symbol: String, title: @escaping @Sendable (_ spaceName: String) -> LocalizedStringResource
    ) {
        self.name = name
        self.symbol = symbol
        self.title = title
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialPromptHeaderKind, rhs: BrowserCredentialPromptHeaderKind) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
