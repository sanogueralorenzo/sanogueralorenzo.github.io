import Foundation

/// A plain glyph a Space's icon can wear, with its name.
struct BrowserSpaceSimpleSymbol: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let work = BrowserSpaceSimpleSymbol(symbol: "briefcase.fill", title: "Work")
    static let personal = BrowserSpaceSimpleSymbol(symbol: "person.fill", title: "Personal")
    static let home = BrowserSpaceSimpleSymbol(symbol: "house.fill", title: "Home")
    static let study = BrowserSpaceSimpleSymbol(symbol: "graduationcap.fill", title: "Study")
    static let creative = BrowserSpaceSimpleSymbol(symbol: "paintbrush.fill", title: "Creative")
    static let games = BrowserSpaceSimpleSymbol(symbol: "gamecontroller.fill", title: "Games")
    static let travel = BrowserSpaceSimpleSymbol(symbol: "airplane", title: "Travel")
    static let grid = BrowserSpaceSimpleSymbol(symbol: "square.grid.2x2", title: "Grid")

    /// Every glyph, in the order they are offered.
    static let all: [BrowserSpaceSimpleSymbol] = [work, personal, home, study, creative, games, travel, grid]

    // MARK: - Variables

    /// The SF Symbol the Space wears.
    let symbol: String
    let title: LocalizedStringResource

    var id: String { symbol }

    // MARK: - Initializers

    private init(symbol: String, title: LocalizedStringResource) {
        self.symbol = symbol
        self.title = title
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpaceSimpleSymbol, rhs: BrowserSpaceSimpleSymbol) -> Bool {
        lhs.symbol == rhs.symbol
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(symbol)
    }
}
