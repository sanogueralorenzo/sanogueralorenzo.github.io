import Foundation

extension BrandColor {
    // MARK: - Static Variables

    static let folderDefault = BrandColor(red: 0.5, green: 0.5, blue: 0.5)
    static let agentDefault = BrandColor(red: 0.53, green: 0.54, blue: 0.56)

    // MARK: - Initializers

    /// An opaque color, each component kept within 0 through 1.
    init(red: Double, green: Double, blue: Double) {
        self.init(clampingRed: red, green: green, blue: blue, alpha: 1)
    }

    /// A color as a color picker or the system gives it, each component kept
    /// within 0 through 1.
    init(clampingRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.init(red: Self.unit(red), green: Self.unit(green), blue: Self.unit(blue), alpha: Self.unit(alpha))
    }

    // MARK: - Actions - Components

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

extension BrandColor: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(red)
        hasher.combine(green)
        hasher.combine(blue)
        hasher.combine(alpha)
    }
}

/// A color as the device's appearance settings store it: its components,
/// opaque unless it says.
extension BrandColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
        case alpha
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            clampingRed: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue),
            alpha: try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
    }
}
