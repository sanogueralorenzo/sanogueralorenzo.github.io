import Foundation

/// Explains automatic engine switches for protected video and lets the
/// person move back after the page has switched.
@MainActor
final class BrowserEngineMoveNotices {
    // MARK: - Variables

    private weak var core: CrestCore?

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
        core.followRehostedPages(self) { [weak self] in self?.rehosted($0) }
    }

    // MARK: - Actions - Moves

    private func rehosted(_ move: PageRehosted) {
        guard move.reason == .protectedMedia, let origin = move.origin else { return }
        let engine = String(localized: move.to.title)
        BrowserNoticeCenter.shared.post(
            BrowserNotice(
                message: String(localized: "Opened in \(engine) for protected video"),
                systemImage: "play.rectangle",
                action: BrowserNoticeAction(title: String(localized: "Move Back")) { [weak self] in
                    self?.core?.open(origin, in: move.spaceID, on: move.from, moving: move.pageID)
                }))
    }
}
