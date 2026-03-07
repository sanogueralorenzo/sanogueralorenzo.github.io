import Foundation

public struct CodexAuthDocument: Codable, Equatable {
    public let auth_mode: String
    public let tokens: CodexAuthTokens
    public let last_refresh: String?
}
