import Foundation

struct BrowserTabIconAccent: Codable, Equatable, Hashable, Sendable {
    // MARK: - Static Variables

    static let white = BrowserTabIconAccent(red: 1, green: 1, blue: 1)

    // MARK: - Variables

    var red: Double
    var green: Double
    var blue: Double

    /// Whether this colour, declared by a page as its theme, is distinctive
    /// enough to stand for the tab.
    var isDistinctive: Bool {
        let brightest = max(red, green, blue)
        let darkest = min(red, green, blue)
        // Page chrome often declares neutral or subtly tinted system surfaces.
        // Defer those to the favicon, whose own neutral colors remain valid.
        return brightest - darkest >= 0.08 && brightest >= 0.18 && darkest <= 0.90
    }

    // MARK: - Initializers

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    // MARK: - Actions - Choosing

    /// This site theme colour when it is distinctive, else the colour
    /// `extracted` from the favicon.
    func preferring(extracted: BrowserTabIconAccent?) -> BrowserTabIconAccent? {
        isDistinctive ? self : extracted
    }
}
