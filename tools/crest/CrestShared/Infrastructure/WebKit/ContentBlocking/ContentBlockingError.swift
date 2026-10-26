import Foundation

enum BrowserContentBlockingError: LocalizedError {
    case compilationFailed
    case ruleListUnavailable

    var errorDescription: String? {
        switch self {
        case .compilationFailed:
            "Crest couldn’t compile its native content-blocking rules."
        case .ruleListUnavailable:
            "Crest’s native content-blocking rules are unavailable."
        }
    }
}
