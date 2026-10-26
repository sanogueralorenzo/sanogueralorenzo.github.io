import Foundation

struct BrowserMacDownloadFlightPath: Equatable {
    let source: CGPoint
    let destination: CGPoint
    let bounds: CGRect

    func point(at progress: Double) -> CGPoint {
        let t = CGFloat(min(max(progress, 0), 1))
        let lift = min(140, hypot(destination.x - source.x, destination.y - source.y) * 0.3)
        let control = CGPoint(
            x: (source.x + destination.x) / 2,
            y: max(bounds.minY + 20, min(source.y, destination.y) - lift)
        )
        return CGPoint(
            x: (1 - t) * (1 - t) * source.x + 2 * (1 - t) * t * control.x + t * t * destination.x,
            y: (1 - t) * (1 - t) * source.y + 2 * (1 - t) * t * control.y + t * t * destination.y
        )
    }

    func scale(at progress: Double) -> CGFloat {
        1 - CGFloat(min(max(progress, 0), 1)) * 0.68
    }
}
