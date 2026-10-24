import SwiftUI
import UIKit

struct MobileTranslationLongPressGesture: UIGestureRecognizerRepresentable {
    private static let minimumPressDuration: TimeInterval = 0.4

    let action: @MainActor () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let gesture = UILongPressGestureRecognizer()
        gesture.minimumPressDuration = Self.minimumPressDuration
        gesture.cancelsTouchesInView = true
        gesture.delegate = context.coordinator
        return gesture
    }

    func handleUIGestureRecognizerAction(_ gesture: UILongPressGestureRecognizer, context: Context) {
        if gesture.state == .began { action() }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The menu's own hold gesture must wait for this shortcut to
            // fail, otherwise UIKit opens its menu while translation starts.
            true
        }
    }
}
