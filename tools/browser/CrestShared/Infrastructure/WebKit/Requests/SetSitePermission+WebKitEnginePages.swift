import Foundation

extension SetSitePermission {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.setSitePermission(self)
    }
}
