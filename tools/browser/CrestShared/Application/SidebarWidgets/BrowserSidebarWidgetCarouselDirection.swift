import Foundation

/// Which way the reader flips through the widget deck.
struct BrowserSidebarWidgetCarouselDirection: Equatable, Sendable {
    // MARK: - Static Variables

    static let previous = Self(
        name: "previous",
        accessibilityLabel: "Previous Widget",
        step: { count in count - 1 }
    )

    static let next = Self(
        name: "next",
        accessibilityLabel: "Next Widget",
        step: { _ in 1 }
    )

    // MARK: - Variables

    let name: String

    /// What a control that flips this way is called.
    let accessibilityLabel: LocalizedStringResource

    /// How many places to advance through a deck of the given size.
    private let step: @Sendable (Int) -> Int

    // MARK: - Initializers

    private init(
        name: String,
        accessibilityLabel: LocalizedStringResource,
        step: @escaping @Sendable (Int) -> Int
    ) {
        self.name = name
        self.accessibilityLabel = accessibilityLabel
        self.step = step
    }

    // MARK: - Actions - Deck

    /// Wrapping adjacency: the deck is a loop the reader flips through, so the
    /// last card hands back to the first rather than dead-ending.
    func adjacentID(
        to selectedID: BrowserSidebarWidgetID?,
        in instances: [BrowserSidebarWidgetInstance]
    ) -> BrowserSidebarWidgetID? {
        guard !instances.isEmpty else { return nil }
        guard
            let selectedID,
            let selectedIndex = instances.firstIndex(where: { $0.id == selectedID })
        else {
            return instances.first?.id
        }
        let count = instances.count
        return instances[(selectedIndex + step(count)) % count].id
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
