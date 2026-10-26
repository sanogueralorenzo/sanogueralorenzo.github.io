import Foundation

/// Whether the reader decides if a widget kind shows.
struct BrowserSidebarWidgetVisibility: Equatable, Sendable {
    // MARK: - Static Variables

    /// The kind always shows wherever it is supported.
    static let mandatory = Self(name: "mandatory", isUserControllable: false)

    /// The reader can turn the kind off in Settings.
    static let userControllable = Self(name: "userControllable", isUserControllable: true)

    // MARK: - Variables

    let name: String

    /// Whether Settings offers the kind as a switch.
    let isUserControllable: Bool

    // MARK: - Initializers

    private init(name: String, isUserControllable: Bool) {
        self.name = name
        self.isUserControllable = isUserControllable
    }

    // MARK: - Actions - Enablement

    /// Whether `kindID` shows, given the kinds the reader turned off.
    func isEnabled(
        _ kindID: BrowserSidebarWidgetKindID,
        disabledKindIdentifiers: Set<String>
    ) -> Bool {
        !isUserControllable || !disabledKindIdentifiers.contains(kindID.rawValue)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
