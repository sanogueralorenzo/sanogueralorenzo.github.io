import Foundation

/// A move through a tab's history an agent asks for, as the navigate tool
/// spells it, and how the tab's page makes it.
struct BrowserAgentNavigationAction: Decodable, Sendable {
    // MARK: - Static Variables

    static let back = Self(name: "back") { core, _ in core.stepHistory(by: -1) }
    static let forward = Self(name: "forward") { core, _ in core.stepHistory(by: 1) }
    static let reload = Self(name: "reload") { _, engine in engine.reload() }

    static let all: [BrowserAgentNavigationAction] = [back, forward, reload]

    // MARK: - Variables

    let name: String
    /// Steps through the tab's history as the core keeps it, or asks its
    /// engine to reload.
    private let move: @MainActor @Sendable (CorePage, EnginePage) -> Void

    // MARK: - Initializers

    private init(name: String, move: @escaping @MainActor @Sendable (CorePage, EnginePage) -> Void) {
        self.name = name
        self.move = move
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let action = Self.all.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Crest has no navigation action \(name).")
        }
        self = action
    }

    // MARK: - Actions - Navigation

    /// Makes the move on the tab's page.
    @MainActor
    func perform(on core: CorePage, _ engine: EnginePage) {
        move(core, engine)
    }
}
