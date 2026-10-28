import UIKit

@MainActor
final class MobileDragReleaseGestureCoordinator: NSObject,
    UIGestureRecognizerDelegate
{
    var release: @MainActor () -> Void

    init(release: @escaping @MainActor () -> Void) {
        self.release = release
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
