import Foundation

extension SplitGroupState.Seed {
    // MARK: - Initializers

    /// A split to seed a Space with, as its member tabs name it, with no
    /// title, icon or tint of its own unless given one.
    init(
        id: UUID = UUID(), customTitle: String? = nil, titleModifiedAt: Date? = nil, customIconSymbol: String? = nil,
        iconModifiedAt: Date? = nil, tint: BrandColor? = nil
    ) {
        self.init(
            id: id, customTitle: customTitle, titleModifiedAt: titleModifiedAt, customIconSymbol: customIconSymbol,
            iconModifiedAt: iconModifiedAt, tint: tint, tintModifiedAt: nil)
    }
}
