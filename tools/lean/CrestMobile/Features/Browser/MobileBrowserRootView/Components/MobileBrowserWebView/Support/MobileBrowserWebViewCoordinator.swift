import UIKit

@MainActor
final class MobileBrowserWebViewCoordinator: NSObject, UIGestureRecognizerDelegate {
    /// Refreshed by the representable so a retained host never dismisses a
    /// sidebar through a stale window's navigation state.
    var handleInteraction: (() -> Void)?

    /// What an unfocused split card does when it is tapped. Refreshed on every
    /// `updateUIView` so the recognizer never holds a stale member's closure.
    var requestFocus: (() -> Void)?

    /// Steps the page back or forward when a finger swipes in from its edge.
    let historySwipe = MobileHistorySwipe()

    lazy var dismissFocusRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(dismissAddressFocus)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    /// The split card's focus tap, on the same terms as the address-focus one:
    /// it observes the tap and the page still gets it.
    lazy var cardFocusRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(requestCardFocus)
        )
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    @objc private func dismissAddressFocus() {
        BrowserAddressFocusDismissal.dismiss()
        handleInteraction?()
    }

    @objc private func requestCardFocus() {
        requestFocus?()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
