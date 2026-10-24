import Foundation

extension PageCaptured {
    @MainActor func deliver(to page: EnginePage) {
        page.captures.removeValue(forKey: captureID)?(png)
    }
}
