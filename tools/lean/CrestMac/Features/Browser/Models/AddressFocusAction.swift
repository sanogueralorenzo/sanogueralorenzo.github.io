import AppKit

@MainActor
enum AddressFocusAction {
    static func perform() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            guard let rootView = window.contentView?.superview else { return }
            guard let field = firstEditableTextField(in: rootView) else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }
    }

    static func resign(keepingFocusIn page: NSView? = nil) {
        guard let window = NSApp.keyWindow else { return }
        resign(in: window, keepingFocusIn: page)
    }

    /// Gives up the responder that owns focus at this selection boundary,
    /// unless it is inside `page`, the page the selection moved to.
    ///
    /// A click in an unfocused split card selects its tab and focuses the
    /// page under the pointer in one gesture, and the click reaches the page
    /// before the selection change reaches here. That focus is where the
    /// person put it: clearing it would blur the field they clicked, and an
    /// engine that keeps no record of its responder, as Chromium does not,
    /// would leave focus nowhere until they clicked again.
    ///
    /// This must remain synchronous. Deferring the clear lets SwiftUI mount the
    /// destination page first, turning an address-focus dismissal into a clear
    /// of that page's newly restored responder instead.
    static func resign(in window: NSWindow, keepingFocusIn page: NSView? = nil) {
        if let page, let responder = window.firstResponder as? NSView, responder.isDescendant(of: page) {
            return
        }
        window.makeFirstResponder(nil)
    }

    private static func firstEditableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for subview in view.subviews {
            if let field = firstEditableTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}
