import Foundation

extension BrowserReaderModeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .articleUnavailable:
            String(localized: BrowserReaderModePresentation.articleUnavailableDescription)
        case .presentationFailed:
            String(localized: BrowserReaderModePresentation.presentationFailedDescription)
        }
    }
}
