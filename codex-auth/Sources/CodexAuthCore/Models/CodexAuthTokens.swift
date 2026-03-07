import Foundation

public struct CodexAuthTokens: Codable, Equatable {
    public let id_token: String
    public let access_token: String
    public let refresh_token: String
    public let account_id: String
}
