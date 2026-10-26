import Foundation

/// The adapter converts native coordinates into a top-left window unit space.
struct BrowserLinkPullSample {
    let location: CGPoint
    let size: CGSize
    let time: TimeInterval

    var isValid: Bool {
        location.x.isFinite && location.y.isFinite
            && size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
            && time.isFinite && time >= 0
    }

    var isInsideWindow: Bool {
        (0...1).contains(location.x) && (0...1).contains(location.y)
    }
}
