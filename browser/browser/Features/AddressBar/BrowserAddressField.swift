import AppKit
import SwiftUI

struct BrowserAddressField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let submit: () -> Void
    let cancel: () -> Void
    var moveSelection: ((Int) -> Void)? = nil
    var tab: (() -> Bool)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.placeholderString = prompt
        field.font = .systemFont(ofSize: 16)
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = prompt
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserAddressField
        init(parent: BrowserAddressField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if selector == NSSelectorFromString("insertNewline:") {
                parent.submit()
                return true
            }
            if selector == NSSelectorFromString("insertTab:") {
                return parent.tab?() ?? false
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
