import AppKit
import SwiftUI

extension EventModifiers {
    /// The modifier keys AppKit reports, as SwiftUI names them.
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}

/// A native single-line editor. The suffix is a noninteractive overlay on
/// its field editor, never an attributed replacement for the entered text.
struct BrowserPlatformCommandPaletteField: NSViewRepresentable {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let identifier: String
    let focused: Bool

    func makeNSView(context: Context) -> NSTextField {
        makeField(coordinator: context.coordinator)
    }

    func makeField(coordinator: Coordinator) -> NSTextField {
        let field = NSTextField(string: model.query)
        field.isBordered = false
        field.drawsBackground = false
        field.font = .preferredFont(forTextStyle: .title2)
        field.placeholderString = String(localized: "Search or Enter URL…")
        field.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.focusRingType = .none
        field.delegate = coordinator
        field.setAccessibilityLabel(String(localized: "Command Palette"))
        field.setAccessibilityIdentifier(identifier)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        coordinator.field = field
        model.applyCompletion = { [weak coordinator = coordinator] text, range in
            coordinator?.insert(text, replacementRange: range)
        }
        model.replaceText = { [weak coordinator = coordinator] text in
            coordinator?.replaceText(text)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let canFocus = context.environment.isEnabled && context.environment.spaceContentIsInteractive
        field.isEditable = canFocus
        field.isSelectable = canFocus
        if !canFocus, let editor = field.currentEditor(), field.window?.firstResponder === editor {
            field.window?.makeFirstResponder(nil)
        }
        if !focused || !canFocus { context.coordinator.didRequestFocus = false }
        if field.currentEditor() == nil, field.stringValue != model.query {
            field.stringValue = model.query
        }
        context.coordinator.refreshSuffix()
        if focused, canFocus, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, coordinator?.field === field, field.isEditable, let window = field.window else {
                    return
                }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.dismantle(field)
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: BrowserCommandPaletteModel
        weak var field: NSTextField?
        let suffixLabel = CompletionLabel(
            rootView: BrowserURLCompletionSuffix(text: "", font: .title2, isVisible: false))
        var didRequestFocus = false
        /// Watches the modifier keys and modified Returns while the field edits.
        private var keyMonitor: Any?

        init(model: BrowserCommandPaletteModel) {
            self.model = model
            super.init()
            suffixLabel.sizingOptions = []
            suffixLabel.setAccessibilityElement(false)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let editor = field?.currentEditor() as? NSTextView else { return }
            editor.isAutomaticTextCompletionEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.addSubview(suffixLabel)
            suffixLabel.nextResponder = editor
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification,
                object: editor)
            watchKeys()
            editingChanged()
        }

        /// While the field edits, a held modifier key shows where Return
        /// opens the selected row, and Return with Command, Shift or Option
        /// opens it there; AppKit sends Command-Return to the menus otherwise.
        private func watchKeys() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                guard let self, let editor = field?.currentEditor(), event.window === field?.window,
                    event.window?.firstResponder === editor
                else { return event }
                model.updateHeldModifiers(EventModifiers(event.modifierFlags))
                guard event.type == .keyDown, Self.returnKeys.contains(event.keyCode),
                    !event.modifierFlags.intersection([.command, .shift, .option]).isEmpty,
                    (editor as? NSTextView)?.hasMarkedText() != true
                else { return event }
                model.pressReturn()
                return nil
            }
        }

        /// Return and the keypad's Enter.
        private static let returnKeys: Set<UInt16> = [36, 76]

        private func stopWatchingKeys() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            model.updateHeldModifiers([])
        }

        @objc private func selectionChanged(_ notification: Notification) { editingChanged() }

        func controlTextDidChange(_ notification: Notification) { editingChanged() }

        func controlTextDidEndEditing(_ notification: Notification) {
            model.rejectURLCompletion()
            stopWatchingKeys()
            detachSuffix()
        }

        func dismantle(_ field: NSTextField) {
            stopWatchingKeys()
            detachSuffix()
            if field.delegate === self { field.delegate = nil }
            if self.field === field { self.field = nil }
            didRequestFocus = false
        }

        private func detachSuffix() {
            NotificationCenter.default.removeObserver(
                self, name: NSTextView.didChangeSelectionNotification, object: nil)
            suffixLabel.rootView.isVisible = false
            suffixLabel.removeFromSuperview()
            suffixLabel.nextResponder = nil
            field?.setAccessibilityHelp(nil)
        }

        func editingChanged() {
            guard let editor = field?.currentEditor() as? NSTextView else { return }
            if editor.undoManager?.isUndoing == true || editor.undoManager?.isRedoing == true {
                model.rejectURLCompletion()
            }
            model.updateCompletionEditing(
                text: editor.string, selection: editor.selectedRange(), isComposing: editor.hasMarkedText())
            refreshSuffix()
        }

        func refreshSuffix() {
            field?.placeholderString =
                model.activeProvider.map { "\($0.actionTitle)…" }
                ?? model.activeScope.map { String(localized: "Search \(String(localized: $0.title))…") }
                ?? String(localized: "Search or Enter URL…")
            if model.urlCompletion == nil, let provider = model.providerOffer {
                suffixLabel.isHidden = true
                suffixLabel.rootView.isVisible = false
                field?.setAccessibilityHelp(String(localized: "\(provider.actionTitle). Press Tab to enter a query."))
                return
            }
            guard let field, let editor = field.currentEditor() as? NSTextView,
                !editor.hasMarkedText(), let proposal = model.urlCompletion,
                let window = editor.window
            else {
                suffixLabel.isHidden = true
                suffixLabel.rootView.isVisible = false
                field?.setAccessibilityHelp(nil)
                return
            }
            let screenRect = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            let rect = editor.convert(window.convertFromScreen(screenRect), from: nil)
            suffixLabel.rootView = BrowserURLCompletionSuffix(
                text: proposal.suffix, font: Font(field.font ?? .preferredFont(forTextStyle: .title2)))
            suffixLabel.frame = NSRect(
                x: rect.maxX, y: rect.minY, width: max(0, editor.bounds.maxX - rect.maxX), height: rect.height)
            suffixLabel.isHidden = false
            field.setAccessibilityHelp(
                String(localized: "URL completion: \(proposal.accepted). Press Tab or Right Arrow to accept."))
        }

        func insert(_ text: String, replacementRange: NSRange) {
            guard let editor = field?.currentEditor() as? NSTextView, !editor.hasMarkedText(),
                editor.string == model.query,
                editor.selectedRange() == NSRange(location: editor.string.utf16.count, length: 0)
            else { return }
            editor.breakUndoCoalescing()
            editor.insertText(text, replacementRange: replacementRange)
            editor.breakUndoCoalescing()
            editingChanged()
        }

        func replaceText(_ text: String) {
            guard let field else { return }
            field.stringValue = text
            field.window?.makeFirstResponder(field)
            if let editor = field.currentEditor() as? NSTextView {
                editor.breakUndoCoalescing()
                editor.string = text
                editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
                editingChanged()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            perform(selector, in: textView, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
        }

        /// Runs the palette's part of an editing command the field received
        /// with `modifiers` held, or answers false to leave it to AppKit.
        /// Control-A and Control-E send the same commands as Option-Up and
        /// Option-Down, so only the modifiers tell them apart.
        func perform(_ selector: Selector, in textView: NSTextView, modifiers: NSEvent.ModifierFlags) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            let shifted = modifiers.contains(.shift)
            let controlHeld = modifiers.contains(.control)
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                model.pressTab()
                refreshSuffix()
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                model.pressBacktab()
                refreshSuffix()
                return true
            case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveToEndOfLine(_:)),
                #selector(NSResponder.moveToEndOfDocument(_:)):
                return model.acceptURLCompletion()
            case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
                if shifted, model.forgetSelectedRow() { return true }
                guard selector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty else {
                    return false
                }
                return model.leaveScope()
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                model.pressReturn()
                return true
            case #selector(NSResponder.moveDown(_:)):
                model.pressDown()
                refreshSuffix()
                return true
            case #selector(NSResponder.moveUp(_:)):
                model.moveSelection(by: -1)
                refreshSuffix()
                return true
            case #selector(NSResponder.moveToEndOfParagraph(_:)):
                // Control-E is the line end: it accepts a completion as Right
                // Arrow does, or AppKit moves there.
                if controlHeld { return model.acceptURLCompletion() }
                model.moveSection(by: 1)
                refreshSuffix()
                return true
            case #selector(NSResponder.moveToBeginningOfParagraph(_:)):
                // Control-A is the line start, which AppKit moves to.
                if controlHeld { return false }
                model.moveSection(by: -1)
                refreshSuffix()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if model.leaveScope() {
                    refreshSuffix()
                    return true
                }
                if model.urlCompletion != nil {
                    model.rejectURLCompletion()
                    refreshSuffix()
                    return true
                }
                return false
            default:
                return false
            }
        }
    }

    final class CompletionLabel: NSHostingView<BrowserURLCompletionSuffix> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }
        override func accessibilityChildren() -> [Any]? { [] }
    }
}
