import Foundation
import WebKit

@MainActor
final class BrowserNavigationDecider {
    func decision(
        for action: WKNavigationAction,
        isAppInitiated: Bool = false
    ) -> BrowserNavigationDecision {
        BrowserNavigationDecision.classify(
            url: action.request.url,
            hasTargetFrame: action.targetFrame != nil,
            shouldPerformDownload: action.shouldPerformDownload,
            isAppInitiated: isAppInitiated
        )
    }

    nonisolated static func decidePolicy(
        canShowMIMEType: Bool,
        response: URLResponse? = nil
    ) -> WKNavigationResponsePolicy {
        switch BrowserNavigationResponseIntent.classify(
            canShowMIMEType: canShowMIMEType,
            response: response
        ) {
        case .display:
            .allow
        case .download:
            .download
        }
    }
}
