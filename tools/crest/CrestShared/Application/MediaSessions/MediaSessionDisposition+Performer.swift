import Foundation

extension MediaSessionDisposition {
    /// Settles an accepted page report on the store, as the core decided.
    @MainActor func settle(
        _ report: BrowserMediaSessionReport, on performer: any BrowserMediaSessionDispositionPerformer
    ) {
        switch self {
        case .retire: performer.retireSession(report)
        case .clear: performer.clearSession(report)
        case .publish: performer.publishSession(report)
        }
    }
}
