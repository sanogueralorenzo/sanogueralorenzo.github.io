import Foundation

/// A revision of the Model Context Protocol Crest's agent helper speaks. A
/// modern revision carries its version and the client's identity on every
/// request; a legacy one opens with an `initialize` handshake that holds for
/// the helper's life.
struct MCPProtocolVersion: Equatable, Sendable {
    // MARK: - Static Variables

    static let july2026 = Self(name: "2026-07-28", isModern: true)
    static let november2025 = Self(name: "2025-11-25", isModern: false)
    static let june2025 = Self(name: "2025-06-18", isModern: false)
    static let march2025 = Self(name: "2025-03-26", isModern: false)
    static let november2024 = Self(name: "2024-11-05", isModern: false)

    /// Every revision the helper speaks, newest first.
    static let all: [Self] = [july2026, november2025, june2025, march2025, november2024]
    /// The newest legacy revision, which a client asking for one the helper
    /// does not speak is offered.
    static let newestLegacy = november2025

    // MARK: - Variables

    let name: String
    let isModern: Bool

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> Self? {
        all.first { $0.name == name }
    }
}
