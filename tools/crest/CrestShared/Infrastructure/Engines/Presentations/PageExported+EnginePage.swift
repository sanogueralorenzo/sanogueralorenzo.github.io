import Foundation

extension PageExported {
    @MainActor func deliver(to page: EnginePage) {
        guard let continuation = page.exports.removeValue(forKey: exportID) else { return }
        if let document {
            continuation.resume(returning: document)
        } else {
            let failure = self.failure ?? PageExportFailure.failed
            continuation.resume(
                throwing: BrowserPageExportError.renderingFailed(String(localized: failure.message)))
        }
    }
}
