import Foundation

/// JSON views for the stored identity spelling contracts.
enum StoredIdentityJSON {
    /// `id` in the stored spelling, as `JSONSerialization` reads it.
    static func wrapped(_ id: UUID) -> [String: String] {
        ["rawValue": id.uuidString]
    }
}
