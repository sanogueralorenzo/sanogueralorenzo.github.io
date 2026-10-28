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
                    guard let core = self?.core, let page = core.state.pages[move.pageID],
                        page.spaceID == move.spaceID, page.engine == move.to,
                        page.live.address.flatMap({ URL(string: $0) }).flatMap({ SiteOrigin(url: $0) }) == origin
                    else { return }
                    _ = try? core.send(RehostPage(pageID: move.pageID, engine: move.from))
                }))
    }
}
