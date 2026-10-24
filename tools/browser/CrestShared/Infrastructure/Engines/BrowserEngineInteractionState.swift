import Foundation

/// Engine payloads remain local, opaque and outside the portable session/sync
/// document. A renderer must never receive another engine's serialized state.
struct BrowserEngineInteractionState: Codable, Equatable {
    private static let magic = Data("CRESTPAGE1\0".utf8)
    let engine: BrowserEngineImplementation.Family
    let version: String
    let payload: Data

    func encoded() -> Data? {
        guard !payload.isEmpty, let body = try? JSONEncoder().encode(self) else { return nil }
        return Self.magic + body
    }

    /// True when `data` names the engine and version that saved it, so that
    /// engine decides whether a restore may read it.
    static func isTagged(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    static func payload(_ data: Data, engine: BrowserEngineImplementation.Family, version: String) -> Data? {
        if isTagged(data) {
            guard let state = try? JSONDecoder().decode(Self.self, from: data.dropFirst(magic.count)),
                state.engine == engine, engine.restoresHistoryFromOtherVersions || state.version == version,
                !state.payload.isEmpty
            else { return nil }
            return state.payload
        }
        // Existing archives predate engine tagging and contain only WebKit data.
        // The outer archive has already checked its OS build and destination.
        return engine == .webKit && !data.isEmpty ? data : nil
    }
}
