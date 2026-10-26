import Foundation

/// A kind of window an agent may ask to open, and how the person is asked
/// about it: the question, which names the agent, the line under it, which
/// names the Space and the address where the agent gives them, and whether
/// the person may let the agent open more without asking. A private window
/// is always asked about.
struct BrowserAgentWindowKind: Equatable, Sendable {
    // MARK: - Static Variables

    static let window = Self(
        name: "window", asksEachTime: false, asking: { String(localized: "Let “\($0)” open a window?") },
        describing: Self.spaceAndAddress)
    static let blankWindow = Self(
        name: "blank", asksEachTime: false, asking: { String(localized: "Let “\($0)” open a Blank Window?") },
        describing: Self.spaceAndAddress)
    static let quickWindow = Self(
        name: "quick", asksEachTime: false, asking: { String(localized: "Let “\($0)” open a Quick Window?") },
        describing: Self.spaceAndAddress)
    static let privateWindow = Self(
        name: "private", asksEachTime: true, asking: { String(localized: "Let “\($0)” open a private window?") },
        describing: { _, address in
            address.map { String(localized: "It opens \($0). Agents never reach into a private window.") }
                ?? String(localized: "Agents never reach into a private window.")
        })

    // MARK: - Variables

    let name: String
    /// Crest asks about every one, even after the person let the agent open
    /// windows without asking.
    let asksEachTime: Bool
    private let asking: @Sendable (String) -> String
    private let describing: @Sendable (_ space: String?, _ address: String?) -> String?

    // MARK: - Initializers

    private init(
        name: String, asksEachTime: Bool, asking: @escaping @Sendable (String) -> String,
        describing: @escaping @Sendable (String?, String?) -> String?
    ) {
        self.name = name
        self.asksEachTime = asksEachTime
        self.asking = asking
        self.describing = describing
    }

    // MARK: - Actions - Questions

    /// The question that asks the person whether the agent `agent` may open
    /// one.
    func question(naming agent: String) -> String {
        asking(agent)
    }

    /// The line under the question, for one over the Space named `space` at
    /// `address`, or nil when there is nothing to add.
    func detail(space: String?, address: String?) -> String? {
        describing(space, address)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    private static func spaceAndAddress(_ space: String?, _ address: String?) -> String? {
        switch (space, address) {
        case (let space?, let address?): String(localized: "It opens \(address) in the \(space) Space.")
        case (let space?, nil): String(localized: "It opens over the \(space) Space.")
        case (nil, _): nil
        }
    }
}
