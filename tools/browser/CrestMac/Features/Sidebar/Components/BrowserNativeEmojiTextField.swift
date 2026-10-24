import AppKit
import SwiftUI

/// Keeps AppKit's real text input client alive while the Character Viewer is
/// frontmost. A SwiftUI `TextField` inside a popover can retain its
/// `FocusState` while AppKit has already replaced the actual first responder
/// with the picker button; the system viewer then has nowhere to insert.
/// Holding the `NSTextField` lets the button restore the native responder
/// immediately before opening the palette.
@MainActor
final class BrowserNativeEmojiTextInputController {
    weak var field: NSTextField?

    func attach(_ field: NSTextField) {
        self.field = field
    }

    func focus() {
        guard let field else { return }
        field.window?.makeFirstResponder(field)
    }

    func presentCharacterPalette() {
        focus()
        DispatchQueue.main.async {
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}

struct BrowserNativeEmojiTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let controller: BrowserNativeEmojiTextInputController
    let commit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, commit: commit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = localizedPlaceholder
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("browser-emoji-icon-field")
        controller.attach(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.commit = commit
        field.placeholderString = localizedPlaceholder
        if field.stringValue != text {
            field.stringValue = text
        }
        controller.attach(field)
    }

    private var localizedPlaceholder: String {
        String(localized: String.LocalizationValue(placeholder))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var commit: () -> Void

        init(text: Binding<String>, commit: @escaping () -> Void) {
            self.text = text
            self.commit = commit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            text.wrappedValue = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:))
            else { return false }
            commit()
            return true
        }
    }
}
