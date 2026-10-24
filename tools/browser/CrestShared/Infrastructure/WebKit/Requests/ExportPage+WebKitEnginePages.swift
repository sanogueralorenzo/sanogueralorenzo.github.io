import Foundation

extension ExportPage {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        pages.export(self)
    }
}
