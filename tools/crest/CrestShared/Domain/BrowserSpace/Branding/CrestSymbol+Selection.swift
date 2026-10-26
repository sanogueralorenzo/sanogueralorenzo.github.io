import Foundation

extension CrestSymbol {
    // MARK: - Static Variables

    /// The figure a crest draws when it names none it can read, as the core
    /// reads it.
    static let fallback = CrestSymbol.mountain

    /// The figures the gallery offers.
    static let selectable: [CrestSymbol] = all.filter(\.isOffered)
}
