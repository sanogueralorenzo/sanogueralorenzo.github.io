import AppKit
import SwiftUI

struct BrowserMiddleClickGesture: NSGestureRecognizerRepresentable {
    let perform: @MainActor () -> Void

    func makeNSGestureRecognizer(context: Context) -> NSClickGestureRecognizer {
        let recognizer = NSClickGestureRecognizer()
        recognizer.buttonMask = 1 << 2
        recognizer.numberOfClicksRequired = 1
        return recognizer
    }

    func handleNSGestureRecognizerAction(
        _ recognizer: NSClickGestureRecognizer,
        context: Context
    ) {
        guard recognizer.state == .ended else { return }
        perform()
    }
}

extension View {
    func browserOnMiddleClick(
        perform: @escaping @MainActor () -> Void
    ) -> some View {
        gesture(BrowserMiddleClickGesture(perform: perform))
    }
}
