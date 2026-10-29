/// The window rules from Crest's catalog. Autoclosures read only the fields
/// this command needs, so a menu item observes its own availability.
enum ShortcutAvailability: Sendable {
    case always, normalSpace, space, webPage, tab, nonStartTab, archive, currentTab, splitCandidate, split

    func allows(
        showsSpace: @autoclosure () -> Bool, isPrivate: @autoclosure () -> Bool,
        surface: @autoclosure () -> TabSurface?, placement: @autoclosure () -> TabPlacement?,
        archived: @autoclosure () -> Bool, candidate: @autoclosure () -> Bool,
        cards: @autoclosure () -> Int
    ) -> Bool {
        switch self {
        case .always: true
        case .normalSpace: showsSpace() && !isPrivate()
        case .space: showsSpace()
        case .webPage: surface()?.showsPage == true
        case .tab: surface() != nil
        case .nonStartTab: surface() != nil && surface() != .startPage
        case .archive: archived()
        case .currentTab: surface() != nil && surface() != .startPage && placement() == .current
        case .splitCandidate: candidate()
        case .split: cards() > 1
        }
    }
}
