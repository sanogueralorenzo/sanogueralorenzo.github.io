import Observation
import WebKit

@MainActor
@Observable
final class BrowserPageLoading {
    enum Indicator: Equatable {
        case hidden
        case loading(since: TimeInterval)
        case revealed(loadingSince: TimeInterval, at: TimeInterval)
    }

    private(set) var showsBackground: Bool
    private(set) var indicator = Indicator.hidden
    @ObservationIgnored var keepsContentForNextNavigation = false
    @ObservationIgnored private var navigationKeepingContent: WKNavigation?
    @ObservationIgnored private var indicatorNavigation: WKNavigation?
    @ObservationIgnored private var pendingPaint: (navigation: WKNavigation?, id: UUID)?

    init(showsBackground: Bool) {
        self.showsBackground = showsBackground
    }

    func started(_ navigation: WKNavigation?) {
        navigationKeepingContent = keepsContentForNextNavigation ? navigation : nil
        keepsContentForNextNavigation = false
        indicatorNavigation = navigation
        indicator = .loading(since: ProcessInfo.processInfo.systemUptime)
    }

    func committed(_ navigation: WKNavigation?, in webView: WKWebView) {
        if let navigationKeepingContent, navigationKeepingContent === navigation {
            self.navigationKeepingContent = nil
            guard showsBackground else { return }
        }
        let paintID = UUID()
        pendingPaint = (navigation, paintID)
        showsBackground = true
        webView.callAsyncJavaScript(Self.waitForPaint, arguments: [:], in: nil, in: .defaultClient) {
            [weak self, weak webView] result in
            guard case .success(let value) = result, value as? Bool == true, let webView else { return }
            self?.revealAfterPresentation(after: paintID, in: webView)
        }
    }

    func finished(_ navigation: WKNavigation?) {
        if let paint = pendingPaint, paint.navigation === navigation {
            Task { [weak self] in
                try await Task.sleep(for: .milliseconds(100))
                self?.reveal(after: paint.id)
            }
        } else if indicatorNavigation === navigation {
            stop()
        }
    }

    func failed(_ navigation: WKNavigation?, committed: Bool) {
        if navigationKeepingContent === navigation { navigationKeepingContent = nil }
        if indicatorNavigation === navigation { stop() }
        if committed, let paint = pendingPaint, paint.navigation === navigation {
            reveal(after: paint.id)
        }
    }

    func stop() {
        indicatorNavigation = nil
        indicator = .hidden
    }

    func invalidate() {
        keepsContentForNextNavigation = false
        navigationKeepingContent = nil
        pendingPaint = nil
        stop()
    }

    private func revealAfterPresentation(after paintID: UUID, in webView: WKWebView) {
        let selector = NSSelectorFromString("_doAfterNextPresentationUpdate:")
        guard pendingPaint?.id == paintID, webView.responds(to: selector) else { return }
        typealias Completion = @convention(block) () -> Void
        typealias Schedule = @convention(c) (AnyObject, Selector, @escaping Completion) -> Void
        let schedule = unsafeBitCast(webView.method(for: selector), to: Schedule.self)
        schedule(webView, selector) { [weak self] in
            MainActor.assumeIsolated { self?.reveal(after: paintID) }
        }
    }

    private func reveal(after paintID: UUID) {
        guard let paint = pendingPaint, paint.id == paintID else { return }
        pendingPaint = nil
        showsBackground = false
        if indicatorNavigation === paint.navigation {
            indicatorNavigation = nil
            if case .loading(let startedAt) = indicator {
                indicator = .revealed(loadingSince: startedAt, at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private static let waitForPaint = #"""
        if (performance.getEntriesByName("first-contentful-paint", "paint").length) return true;
        if (!globalThis.PerformanceObserver?.supportedEntryTypes?.includes("paint")) return false;
        return new Promise(resolve => {
            const observer = new PerformanceObserver(list => {
                if (!list.getEntries().some(entry => entry.name === "first-contentful-paint")) return;
                observer.disconnect();
                resolve(true);
            });
            observer.observe({type: "paint", buffered: true});
        });
        """#
}
