import AppKit
import SwiftUI

/// A native address editor that takes focus when it is attached, including at launch.
struct BrowserAddressField: NSViewRepresentable {
    @Binding var text: String
    let submit: () -> Void
    let cancel: () -> Void
    var moveSelection: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.placeholderString = "Search or Enter URL…"
        field.font = .systemFont(ofSize: 18)
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserAddressField
        init(parent: BrowserAddressField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == NSSelectorFromString("insertNewline:") {
                parent.submit()
                return true
            }
            if selector == NSSelectorFromString("moveDown:") {
                parent.moveSelection?(1)
                return true
            }
            if selector == NSSelectorFromString("moveUp:") {
                parent.moveSelection?(-1)
                return true
            }
            if selector == NSSelectorFromString("cancelOperation:") {
                parent.cancel()
                return true
            }
            return false
        }
    }

    final class Field: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            window?.makeFirstResponder(self)
            currentEditor()?.selectAll(nil)
        }
    }
}
