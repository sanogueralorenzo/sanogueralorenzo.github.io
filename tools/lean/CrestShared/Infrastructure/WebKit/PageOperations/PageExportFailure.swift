import Foundation

enum PageExportFailure: Hashable, Sendable {
    case busy, unsupported, closed, navigated, rendererStopped, timedOut, tooLarge, failed

    var message: LocalizedStringResource {
        switch self {
        case .busy: "An export is already in progress for this page."
        case .unsupported: "This page cannot be exported."
        case .closed: "The page was closed."
        case .navigated: "The page navigated before its export finished."
        case .rendererStopped: "The page renderer stopped."
        case .timedOut: "The page export timed out."
        case .tooLarge: "The page export is too large."
        case .failed: "The page could not be exported."
        }
    }
}
