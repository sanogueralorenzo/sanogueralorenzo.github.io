import Foundation

enum BrowserPageExportError: LocalizedError {
    case pageUnavailable
    case renderingFailed(String)

    var errorDescription: String? {
        switch self {
        case .pageUnavailable:
            "There is no loaded page to export."
        case .renderingFailed(let message):
            message
        }
    }
}
