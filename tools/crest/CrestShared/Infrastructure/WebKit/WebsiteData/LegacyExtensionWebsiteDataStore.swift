import CryptoKit
import Foundation

/// Identifies the obsolete cookie-copying store for site-data and profile
/// deletion. New extension documents never load this store.
@MainActor
enum BrowserLegacyExtensionWebsiteDataStore {
    static func identifier(forProfileID profileID: UUID) -> UUID {
        let digest = Array(
            SHA256.hash(data: Data("crest.extension-hosted-storage.\(profileID.uuidString.lowercased())".utf8)))
        return UUID(
            uuid: (
                digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
                (digest[6] & 0x0f) | 0x50, digest[7], (digest[8] & 0x3f) | 0x80, digest[9],
                digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
            ))
    }
}
