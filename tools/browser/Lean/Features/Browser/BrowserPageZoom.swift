import Foundation

enum BrowserPageZoom {
    static let levels: [Double] = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    static func step(_ zoom: Double, increasing: Bool) -> Double {
        if increasing { return levels.first { $0 > zoom + 0.001 } ?? max(zoom, levels.last!) }
        return levels.last { $0 < zoom - 0.001 } ?? min(zoom, levels.first!)
    }
}
