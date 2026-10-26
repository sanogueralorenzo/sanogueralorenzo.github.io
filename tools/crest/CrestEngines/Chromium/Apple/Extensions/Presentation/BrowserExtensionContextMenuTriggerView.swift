import AppKit

/// Catches only secondary clicks. A SwiftUI button keeps its ordinary primary
/// click while this overlay quietly adds the right-click and Control-click a
/// native extension button is expected to answer.
final class BrowserExtensionContextMenuTriggerView: NSView {
    var presentMenu: ((NSEvent) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, Self.isSecondary(event) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        presentMenu?(event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else {
            super.mouseDown(with: event)
            return
        }
        presentMenu?(event)
    }

    private static func isSecondary(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            true
        case .leftMouseDown, .leftMouseUp:
            event.modifierFlags.contains(.control)
        default:
            false
        }
    }
}
