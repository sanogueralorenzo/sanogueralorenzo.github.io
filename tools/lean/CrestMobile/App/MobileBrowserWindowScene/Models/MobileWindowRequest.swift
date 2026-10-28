import Foundation

/// What iPadOS restores a browser window scene with: the window's identity.
///
/// It is coded as `{"rawValue": UUID}`, the spelling the scene value had when
/// it was the window's ID wrapper, so a window saved by an earlier build comes
/// back under its own record. A bare UUID reads too.
struct MobileWindowRequest: Hashable, Sendable {
    // MARK: - Variables

    let id: UUID

    // MARK: - Initializers

    init(id: UUID = UUID()) {
        self.id = id
    }
}

// MARK: - Codable

extension MobileWindowRequest: Codable {
    init(from decoder: any Decoder) throws {
        id = try decoder.decodeIdentity()
    }

    func encode(to encoder: any Encoder) throws {
        try encoder.encodeStoredIdentity(id)
    }
}
