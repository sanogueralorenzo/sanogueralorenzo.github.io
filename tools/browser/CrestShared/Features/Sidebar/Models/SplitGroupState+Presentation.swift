import Foundation

/// What a split's row draws from the choices a person made for it, as the core
/// resolved them.
extension SplitGroupState {
    /// A split no one made a choice for yet, such as one whose choices have
    /// not arrived.
    static func unchosen(_ id: UUID) -> SplitGroupState {
        SplitGroupState(
            id: id, customTitle: nil, titleModifiedAt: nil, customIconSymbol: nil, iconModifiedAt: nil, tint: nil,
            tintModifiedAt: nil, displayTitle: nil, displayEmojiIcon: nil)
    }

    /// The name the split's row shows: the one a person gave it, or the core's
    /// stand-in for a split no one named.
    var shownTitle: String {
        displayTitle ?? String(localized: defaultTitle)
    }
}
