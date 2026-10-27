import Foundation

enum BrowserPageZoom {
    static let levels: [Double] = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static func step(_ zoom: Double, increasing: Bool) -> Double {
        if increasing { return levels.first { $0 > zoom + 0.001 } ?? max(zoom, levels.last!) }
        return levels.last { $0 < zoom - 0.001 } ?? min(zoom, levels.first!)
    }
}

extension BrowserStore {
    func setDefaultPageZoom(_ zoom: Double) {
        guard zoom.isFinite, (0.25...5).contains(zoom) else { return }
        let previous = preferences.defaultPageZoom ?? 1
        for s in session.spaces.indices {
            for t in session.spaces[s].tabs.indices {
                let id = session.spaces[s].tabs[t].id
                let current = pages[id].map { Double($0.webView.pageZoom) } ?? session.spaces[s].tabs[t].zoom
                if abs(current - previous) < 0.0001 {
                    session.spaces[s].tabs[t].zoom = zoom
                    pages[id]?.webView.pageZoom = zoom
                }
            }
        }
        updatePreferences { $0.defaultPageZoom = zoom }
    }
}
