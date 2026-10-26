import Foundation

/// A Next or Previous Space command's move in one window: from the Space it
/// showed to the one beside it, around the ends when it wraps. The Space pager
/// slides a step as it does between neighbours, while choosing a distant Space,
/// such as the last one from the first, shows it without a slide.
struct BrowserSpaceStep: Equatable {
    // MARK: - Variables

    /// Tells this step from an earlier one between the same two Spaces.
    let id = UUID()
    let origin: UUID
    let destination: UUID
    let direction: BrowserSpaceSwipeDirection

    // MARK: - Actions - Following

    /// The way this step went from `origin` to `destination`, when it is the
    /// move between them; nil for any other move.
    func direction(from origin: UUID, to destination: UUID) -> BrowserSpaceSwipeDirection? {
        origin == self.origin && destination == self.destination ? direction : nil
    }
}
