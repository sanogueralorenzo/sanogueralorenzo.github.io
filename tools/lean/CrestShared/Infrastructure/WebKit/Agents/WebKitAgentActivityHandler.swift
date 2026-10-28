import Foundation
import WebKit

#if os(macOS)
    // MARK: - Types

    /// What the activity observer in a watched page's world posts: a console
    /// message or an error, or a resource the page loaded. The page's own
    /// scripts can post too, so nothing here is trusted beyond being kept for
    /// the agent watching that page.
    struct WebKitAgentActivityMessage: Decodable {
        /// A console message's level, as the observer spells it.
        enum Level: String, Decodable {
            case debug
            case log
            case info
            case warning
            case error

            var engineLevel: PageConsoleLevel {
                switch self {
                case .debug: .debug
                case .log: .log
                case .info: .info
                case .warning: .warning
                case .error: .error
                }
            }
        }

        let kind: WebKitAgentActivityKind
        let level: Level?
        let text: String?
        let source: String?
        let line: Int?
        let url: String?
        let type: String?
        let status: Int?
        let duration: Double?
        let bytes: Double?
        let start: Double?
    }

    /// Hears the activity observer of one watched page, and stops hearing it
    /// once the agent stops watching. A popup shares its opener's controller,
    /// so its observer reaches this handler too; only the watched page's own
    /// view is heard.
    final class WebKitAgentActivityHandler: NSObject, WKScriptMessageHandler {
        // MARK: - Variables

        private let pageID: UUID
        private weak var webView: WKWebView?
        private var keep: (@MainActor (UUID, WebKitAgentActivityMessage) -> Void)?

        // MARK: - Initializers

        init(
            pageID: UUID, webView: WKWebView, keep: @escaping @MainActor (UUID, WebKitAgentActivityMessage) -> Void
        ) {
            self.pageID = pageID
            self.webView = webView
            self.keep = keep
        }

        // MARK: - Actions - Messages

        func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            MainActor.assumeIsolated {
                guard let keep, let webView, message.webView === webView, message.frameInfo.isMainFrame,
                    JSONSerialization.isValidJSONObject(message.body),
                    let data = try? JSONSerialization.data(withJSONObject: message.body),
                    let activity = try? JSONDecoder().decode(WebKitAgentActivityMessage.self, from: data)
                else { return }
                keep(pageID, activity)
            }
        }

        /// The agent stopped watching the page.
        func stop() {
            keep = nil
        }
    }
#endif
