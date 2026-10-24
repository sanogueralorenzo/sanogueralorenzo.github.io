import Foundation

extension FindFinished {
    @MainActor func deliver(to page: EnginePage) {
        let completion = page.findCompletion
        page.findCompletion = nil
        completion?(
            matches.map { BrowserFindResult(matchCount: $0, activeMatch: activeMatch) }
                ?? BrowserFindResult(matchFound: true))
    }
}
