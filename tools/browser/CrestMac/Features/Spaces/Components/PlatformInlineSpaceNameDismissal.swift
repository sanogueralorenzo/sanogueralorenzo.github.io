import AppKit
import SwiftUI

/// Observe without consuming the click: the first outside click both ends title
/// editing and performs the newly chosen action.
struct PlatformInlineSpaceNameDismissal: NSViewRepresentable {
    let isEditing: Bool
    let finish: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.isEditing = isEditing
        view.finish = finish
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }

    final class ObserverView: NSView {
        var isEditing = false
        var finish: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                guard let self, self.isEditing, event.window === self.window else { return event }
                if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.finish() }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
