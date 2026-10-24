import SwiftUI
import UIKit

/// Tells `action` about a tap inside the content without taking part in the
/// tap. A SwiftUI tap gesture on a container competes with the controls inside
/// it, and an iPad pointer's click goes to the container instead of the button
/// under it; this watches from the window, which sees every touch, and never
/// claims one.
///
/// The window sees a touch wherever it lands, so content drawn over other
/// observed content, such as a sidebar floating over the page, claims its
/// taps: an observer beneath it does not hear a tap inside it. Otherwise a tap
/// on the sidebar's buttons would also read as a tap on the page, which hides
/// the sidebar before its button can act.
struct BrowserPlatformObservedTapModifier: ViewModifier {
    var claimsTaps = false
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        content.background(BrowserObservedTapAnchor(claimsTaps: claimsTaps, action: action))
    }
}

/// Marks where the content is, and keeps the window's observer while it's on
/// screen.
private struct BrowserObservedTapAnchor: UIViewRepresentable {
    let claimsTaps: Bool
    let action: @MainActor () -> Void

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.action = action
        view.claimsTaps = claimsTaps
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.action = action
        view.claimsTaps = claimsTaps
    }

    final class AnchorView: UIView {
        // MARK: - Static Variables

        /// The anchors on screen whose content keeps its taps from the
        /// observers beneath it.
        private static let claiming = NSHashTable<AnchorView>.weakObjects()

        // MARK: - Variables

        var action: (@MainActor () -> Void)?
        var claimsTaps = false {
            didSet { register() }
        }
        private var observer: BrowserTapObserverRecognizer?

        // MARK: - Actions - Window

        override func didMoveToWindow() {
            super.didMoveToWindow()
            register()
            if let observer {
                observer.view?.removeGestureRecognizer(observer)
                self.observer = nil
            }
            guard let window else { return }
            let observer = BrowserTapObserverRecognizer { [weak self] touch in
                guard let self, self.window != nil, self.contains(touch),
                    self.claimsTaps || !Self.isClaimed(touch)
                else { return }
                self.action?()
            }
            window.addGestureRecognizer(observer)
            self.observer = observer
        }

        // MARK: - Actions - Claims

        private func register() {
            if claimsTaps, window != nil {
                Self.claiming.add(self)
            } else {
                Self.claiming.remove(self)
            }
        }

        /// Whether content that claims its taps is on screen where `touch`
        /// landed.
        private static func isClaimed(_ touch: UITouch) -> Bool {
            claiming.allObjects.contains { $0.window === touch.window && $0.isShown && $0.contains(touch) }
        }

        private func contains(_ touch: UITouch) -> Bool {
            bounds.contains(touch.location(in: self))
        }

        /// Whether the anchor and everything holding it are drawn.
        private var isShown: Bool {
            sequence(first: self as UIView, next: \.superview).allSatisfy { !$0.isHidden && $0.alpha > 0 }
        }
    }
}

/// Sees a touch end close to where it began, reports it, and fails, so it
/// never holds up, cancels or outranks anything else the touch reaches.
private final class BrowserTapObserverRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private static let slop: CGFloat = 10
    private let tapped: @MainActor (UITouch) -> Void
    private var start: CGPoint?

    init(tapped: @escaping @MainActor (UITouch) -> Void) {
        self.tapped = tapped
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first, start == nil else {
            state = .failed
            return
        }
        start = touch.location(in: nil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, let touch = touches.first else { return }
        let point = touch.location(in: nil)
        if hypot(point.x - start.x, point.y - start.y) > Self.slop { state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let touch = touches.first { tapped(touch) }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        start = nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
