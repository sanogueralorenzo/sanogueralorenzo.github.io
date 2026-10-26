import Foundation

extension PageMedia {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        PageMediaState(activity: pages.page(pageID).map(pages.mediaActivity) ?? [])
    }
}
