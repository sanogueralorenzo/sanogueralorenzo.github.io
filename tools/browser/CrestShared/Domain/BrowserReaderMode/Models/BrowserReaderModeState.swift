import Foundation

/// Where a page stands with Reader, from unprobed to showing.
struct BrowserReaderModeState: Hashable, Sendable {
    // MARK: - Static Variables

    static let unavailable = BrowserReaderModeState(
        name: "unavailable", canToggle: false, isAvailable: false, isActive: false)
    static let checking = BrowserReaderModeState(
        name: "checking", canToggle: false, isAvailable: false, isActive: false)
    static let available = BrowserReaderModeState(
        name: "available", canToggle: true, isAvailable: true, isActive: false)
    static let activating = BrowserReaderModeState(
        name: "activating", canToggle: false, isAvailable: true, isActive: false)
    static let active = BrowserReaderModeState(
        name: "active", canToggle: true, isAvailable: true, isActive: true)

    /// Every state, in the order a page moves through them.
    static let all: [BrowserReaderModeState] = [unavailable, checking, available, activating, active]

    // MARK: - Variables

    let name: String

    /// Whether the Reader command can act now.
    let canToggle: Bool

    /// Whether reader mode is known to be offerable for the current page. A
    /// state that has not been probed yet reports `false` rather than forcing a
    /// probe, so a caller reading this never blocks on the page.
    let isAvailable: Bool

    let isActive: Bool

    /// The Reader command's name, which turns Reader off while it shows.
    var actionTitle: LocalizedStringResource { isActive ? "Hide Reader" : "Show Reader" }

    /// The Reader command's symbol, filled while Reader shows.
    var actionSymbol: String { isActive ? "doc.plaintext.fill" : "doc.plaintext" }

    // MARK: - Initializers

    private init(name: String, canToggle: Bool, isAvailable: Bool, isActive: Bool) {
        self.name = name
        self.canToggle = canToggle
        self.isAvailable = isAvailable
        self.isActive = isActive
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserReaderModeState, rhs: BrowserReaderModeState) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
