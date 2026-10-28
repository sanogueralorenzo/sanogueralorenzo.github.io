import Foundation
import WebKit

// MARK: - Types

enum BrowserReaderModeAction: String, CaseIterable, Sendable {
    case availability
    case activate
    case deactivate
    case snapshot
}

@MainActor
enum BrowserReaderModeController {
    static let contentWorld = WKContentWorld.world(name: "Crest.ReaderMode")

    static func isAvailable(in webView: WKWebView) async throws -> Bool {
        try await perform(.availability, in: webView) as? Bool == true
    }

    static func activate(in webView: WKWebView) async throws {
        guard try await perform(.activate, in: webView) as? Bool == true else {
            throw BrowserReaderModeError.articleUnavailable
        }
    }

    static func deactivate(in webView: WKWebView) async throws {
        guard try await perform(.deactivate, in: webView) as? Bool == true else {
            throw BrowserReaderModeError.presentationFailed
        }
    }

    static func snapshot(in webView: WKWebView) async throws -> BrowserReaderModeSnapshot {
        try BrowserReaderModeSnapshotDecoder.decode(
            try await perform(.snapshot, in: webView)
        )
    }

    private static func perform(
        _ action: BrowserReaderModeAction,
        in webView: WKWebView
    ) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            BrowserReaderModeJavaScriptBridge.source,
            arguments: [
                "action": action.rawValue,
                "readerModeLabel": String(
                    localized: BrowserReaderModePresentation.accessibilityLabel
                ),
            ],
            in: nil,
            contentWorld: contentWorld
        )
    }
}
