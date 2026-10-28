import SwiftUI
import UIKit

struct MobileDragReleaseGesture: UIGestureRecognizerRepresentable {
    let release: @MainActor () -> Void

    func makeCoordinator(
        converter: CoordinateSpaceConverter
    ) -> MobileDragReleaseGestureCoordinator {
        MobileDragReleaseGestureCoordinator(release: release)
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        context.coordinator.release = release
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .ended, .cancelled, .failed:
            context.coordinator.release()
        default:
            break
        }
    }
}
