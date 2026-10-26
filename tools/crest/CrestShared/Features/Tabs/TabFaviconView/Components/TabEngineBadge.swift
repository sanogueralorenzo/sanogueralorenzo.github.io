import SwiftUI

/// The badge a tab's icon wears while its page runs on an engine the core
/// badges: on a device with more than one engine, every engine but the one new
/// pages open on. It draws that engine's mark, and follows the page live, so
/// moving the page to another engine redraws only this badge. A tab without a
/// page, or whose engine has no mark, wears none.
///
/// It reads the core from the environment and draws nothing where no window
/// supplies one, such as a drag preview, or while a status badge has taken
/// its corner.
struct TabEngineBadge: View {
    // MARK: - Variables

    let tabID: UUID

    /// The favicon's scale against a default-density row's.
    var scale: CGFloat = 1

    @Environment(CrestCore.self) private var core: CrestCore?
    @Environment(\.tabFaviconBadgeIsTaken) private var isCornerTaken

    var body: some View {
        if !isCornerTaken, let engine = core?.state.engineBadge(forTab: tabID), let mark = engine.mark {
            TabFaviconBadge(mark: mark, title: Text(engine.pageDescription), scale: scale)
        }
    }
}
