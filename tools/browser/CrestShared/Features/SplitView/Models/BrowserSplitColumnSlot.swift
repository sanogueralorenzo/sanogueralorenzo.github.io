import Foundation

/// One column of the split-view row.
///
/// A drag in flight adds a column rather than decorating the row with one. The
/// slot the dragged tab would land in is laid out, wrapped, and measured exactly
/// as a member's card is: same surface, same gap, same share of the container.
/// Only its interior differs, and only until the drop replaces it with the card
/// it was standing in for.
///
/// Identity is what makes that replacement read as a replacement. A member keeps
/// its `UUID` for the life of the row, so the cards a drag never touched are
/// never remounted — which matters more here than in an ordinary list, because a
/// remounted card would hand a live `WKWebView` to a second superview. The
/// placeholder and extension panel have distinct identities without tabs:
/// on release the placeholder leaves and the joining member arrives in the same
/// position at the same width, and every other column holds still.
enum BrowserSplitColumnSlot<Member: Identifiable>: Identifiable where Member.ID == UUID {
    case member(Member)
    /// The column a drag in flight would drop into.
    case placeholder
    case panel

    var id: BrowserSplitColumnSlotID {
        switch self {
        case .member(let tab): .member(tab.id)
        case .placeholder: .placeholder
        case .panel: .panel
        }
    }

    var member: Member? {
        switch self {
        case .member(let tab): tab
        case .placeholder, .panel: nil
        }
    }

    /// The slots a row of `members` lays out, with the drop column opened at
    /// `placeholderIndex` when a drag has resolved one.
    ///
    /// An index outside `0...members.count` is not a slot, so the row lays out
    /// as though no drag were in flight.
    static func slots(
        members: [Member],
        placeholderIndex: Int?,
        includesPanel: Bool = false
    ) -> [BrowserSplitColumnSlot] {
        var slots = members.map(BrowserSplitColumnSlot.member)
        if let placeholderIndex,
            placeholderIndex >= 0,
            placeholderIndex <= members.count
        {
            slots.insert(.placeholder, at: placeholderIndex)
        }
        if includesPanel { slots.append(.panel) }
        return slots
    }
}

enum BrowserSplitColumnSlotID: Hashable {
    case member(UUID)
    case placeholder
    case panel
}
