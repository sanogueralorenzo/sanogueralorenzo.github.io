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
    @ObservationIgnored private var indicatorNavigation: WKNavigation?
    @ObservationIgnored private var pendingPaint: (navigation: WKNavigation?, id: UUID)?

    init(showsBackground: Bool) {
        self.showsBackground = showsBackground
    }

    func started(_ navigation: WKNavigation?) {
        indicatorNavigation = navigation
        indicator = .loading(since: ProcessInfo.processInfo.systemUptime)
    }

    func committed(_ navigation: WKNavigation?, in webView: WKWebView) {
        let paintID = UUID()
        pendingPaint = (navigation, paintID)
        showsBackground = true
        webView.callAsyncJavaScript(Self.waitForPaint, arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
            if case .success = result { self?.reveal(after: paintID) }
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
        pendingPaint = nil
        stop()
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
        return new Promise(resolve => {
            let observer;
            const painted = () => {
                observer?.disconnect();
                removeEventListener("load", painted);
                requestAnimationFrame(() => requestAnimationFrame(() => resolve(true)));
            };
            if (document.readyState === "complete") {
                painted();
                return;
            }
            if (PerformanceObserver.supportedEntryTypes.includes("paint")) {
                observer = new PerformanceObserver(painted);
                observer.observe({type: "paint", buffered: true});
            }
            addEventListener("load", painted, {once: true});
        });
        """#
}
