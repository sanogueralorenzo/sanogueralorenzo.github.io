@MainActor
final class BrowserSpaceDataReleaseProbe {
    private weak var object: AnyObject?

    init(_ object: AnyObject) {
        self.object = object
    }

    var isReleased: Bool { object == nil }
}
