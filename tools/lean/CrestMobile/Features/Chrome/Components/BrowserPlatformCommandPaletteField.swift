import SwiftUI
import UIKit

extension EventModifiers {
    /// The modifier keys UIKit reports, as SwiftUI names them.
    init(_ flags: UIKeyModifierFlags) {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}

extension UIKeyModifierFlags {
    /// The modifier keys SwiftUI names, as UIKit reports them.
    init(_ modifiers: EventModifiers) {
        var flags: UIKeyModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.alternate) }
        if modifiers.contains(.control) { flags.insert(.control) }
        self = flags
    }
}

struct BrowserPlatformCommandPaletteField: UIViewRepresentable {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let identifier: String
    let focused: Bool

    func makeUIView(context: Context) -> CompletionField {
        makeField(coordinator: context.coordinator)
    }

    func makeField(coordinator: Coordinator) -> CompletionField {
        let field = CompletionField()
        field.text = model.query
        field.font = .preferredFont(forTextStyle: .title2)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = String(localized: "Search or Enter URL…")
        // A URL keyboard would remove the space bar multi-word searches need.
        field.keyboardType = .default
        field.textContentType = nil
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .go
        field.accessibilityLabel = String(localized: "Command Palette")
        field.accessibilityIdentifier = identifier
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = coordinator
        field.model = model
        field.addTarget(coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        coordinator.field = field
        model.applyCompletion = { [weak coordinator = coordinator] text, range in
            coordinator?.insert(text, replacementRange: range)
        }
        model.replaceText = { [weak field] text in
            guard let field else { return }
            field.text = text
            field.sendActions(for: .editingChanged)
        }
        return field
    }

    func updateUIView(_ field: CompletionField, context: Context) {
        if !field.isFirstResponder, field.text != model.query { field.text = model.query }
        field.refreshSuffix()
        if focused, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            DispatchQueue.main.async { [weak field] in
                guard let field else { return }
                field.becomeFirstResponder()
                field.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        let model: BrowserCommandPaletteModel
        weak var field: CompletionField?
        var didRequestFocus = false

        init(model: BrowserCommandPaletteModel) { self.model = model }

        @objc func editingChanged() {
            guard let field, let range = field.selectedTextRange else { return }
            model.updateCompletionEditing(
                text: field.text ?? "",
                selection: NSRange(
                    location: field.offset(from: field.beginningOfDocument, to: range.start),
                    length: field.offset(from: range.start, to: range.end)),
                isComposing: field.markedTextRange != nil
            )
            field.refreshSuffix()
        }

        func textFieldDidChangeSelection(_ textField: UITextField) { editingChanged() }
        func textFieldDidBeginEditing(_ textField: UITextField) { editingChanged() }
        func textFieldDidEndEditing(_ textField: UITextField) {
            model.rejectURLCompletion()
            field?.refreshSuffix()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard textField.markedTextRange == nil else { return false }
            model.pressReturn()
            return false
        }

        /// Delete in an empty field leaves the site search or scope.
        func textField(
            _ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String
        )
            -> Bool
        {
            guard string.isEmpty, range.length == 0, (textField.text ?? "").isEmpty else { return true }
            return !model.leaveScope()
        }

        func insert(_ text: String, replacementRange: NSRange) {
            guard let field, field.markedTextRange == nil, field.text == model.query,
                let range = field.selectedTextRange, range.isEmpty,
                field.compare(range.end, to: field.endOfDocument) == .orderedSame
            else { return }
            guard let start = field.position(from: field.beginningOfDocument, offset: replacementRange.location),
                let end = field.position(from: start, offset: replacementRange.length),
                let replacement = field.textRange(from: start, to: end)
            else { return }
            field.selectedTextRange = replacement
            field.insertText(text)
            editingChanged()
        }
    }

    final class CompletionField: UITextField {
        weak var model: BrowserCommandPaletteModel?
        private let suffixLabel = UIHostingConfiguration {
            BrowserURLCompletionSuffix(text: "", font: .title2, isVisible: false)
        }.margins(.all, 0).makeContentView()
        private var renderedSuffix = ""
        private var renderedFont: UIFont?

        override init(frame: CGRect) {
            super.init(frame: frame)
            suffixLabel.isAccessibilityElement = false
            suffixLabel.isUserInteractionEnabled = false
            suffixLabel.isHidden = true
            addSubview(suffixLabel)
            clipsToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// A hardware keyboard's Tab runs the palette's Tab chain, Shift-Tab
        /// moves back, Right Arrow accepts the completion, and Return with
        /// Command, Shift or Option opens the row where those keys choose.
        override var keyCommands: [UIKeyCommand]? {
            guard markedTextRange == nil else { return super.keyCommands }
            var commands = [
                command("\t", [], #selector(pressTab), String(localized: "Complete or Search Site")),
                command("\t", .shift, #selector(pressBacktab), nil),
                command(UIKeyCommand.inputEscape, [], #selector(pressEscape), nil),
            ]
            if model?.urlCompletion != nil {
                commands.append(command(UIKeyCommand.inputRightArrow, [], #selector(acceptCompletion), nil))
            }
            for opening in model?.openings ?? [] where !opening.modifiers.isEmpty {
                commands.append(command("\r", UIKeyModifierFlags(opening.modifiers), #selector(pressReturn(_:)), nil))
            }
            return (super.keyCommands ?? []) + commands
        }

        private func command(_ input: String, _ modifiers: UIKeyModifierFlags, _ action: Selector, _ title: String?)
            -> UIKeyCommand
        {
            let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
            if let title { command.discoverabilityTitle = title }
            command.wantsPriorityOverSystemBehavior = true
            return command
        }

        @objc private func acceptCompletion() {
            model?.acceptURLCompletion()
            refreshSuffix()
        }

        @objc private func pressTab() {
            model?.pressTab()
            refreshSuffix()
        }

        @objc private func pressBacktab() {
            model?.pressBacktab()
        }

        @objc private func pressEscape() {
            guard let model else { return }
            if model.leaveScope() { return }
            if model.urlCompletion != nil {
                model.rejectURLCompletion()
                refreshSuffix()
            } else {
                model.dismiss()
            }
        }

        @objc private func pressReturn(_ command: UIKeyCommand) {
            model?.updateHeldModifiers(EventModifiers(command.modifierFlags))
            model?.pressReturn()
        }

        /// A held modifier key shows where Return opens the selected row.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            model?.updateHeldModifiers(EventModifiers(event?.modifierFlags ?? []))
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            model?.updateHeldModifiers(
                EventModifiers(event?.modifierFlags ?? []).subtracting(
                    EventModifiers(presses.compactMap(\.key?.modifierFlags).reduce([]) { $0.union($1) })))
            super.pressesEnded(presses, with: event)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            refreshSuffix()
        }

        func refreshSuffix() {
            guard isFirstResponder, markedTextRange == nil,
                let proposal = model?.urlCompletion, let range = selectedTextRange
            else {
                if !suffixLabel.isHidden {
                    suffixLabel.isHidden = true
                    suffixLabel.configuration = UIHostingConfiguration {
                        BrowserURLCompletionSuffix(text: "", font: .title2, isVisible: false)
                    }.margins(.all, 0)
                }
                accessibilityHint = nil
                return
            }
            let caret = caretRect(for: range.end)
            if suffixLabel.isHidden || renderedSuffix != proposal.suffix || renderedFont != font {
                renderedSuffix = proposal.suffix
                renderedFont = font
                let suffixFont = Font(font ?? .preferredFont(forTextStyle: .title2))
                suffixLabel.configuration = UIHostingConfiguration {
                    BrowserURLCompletionSuffix(text: proposal.suffix, font: suffixFont)
                }.margins(.all, 0)
            }
            suffixLabel.frame = CGRect(
                x: caret.maxX, y: caret.minY, width: max(0, bounds.maxX - caret.maxX), height: caret.height)
            suffixLabel.isHidden = false
            accessibilityHint = String(
                localized: "URL completion: \(proposal.accepted). Press Tab or Right Arrow to accept.")
        }
    }
}
