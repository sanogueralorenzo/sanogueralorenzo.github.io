import AppKit
import SwiftUI

struct BrowserShortcutRecorder: NSViewRepresentable {
    @Environment(\.locale) private var locale

    let identifier: String
    let title: String
    let shortcut: BrowserShortcut?
    let record: (BrowserShortcut?) -> Void
    let reportInvalidShortcut: () -> Void

    func makeCoordinator() -> BrowserShortcutRecorderCoordinator {
        BrowserShortcutRecorderCoordinator(
            record: record,
            reportInvalidShortcut: reportInvalidShortcut
        )
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .monospacedSystemFont(
            ofSize: BrowserShortcutSettingsMetrics.recorderFontSize,
            weight: .medium
        )
        button.target = context.coordinator
        button.action = #selector(
            BrowserShortcutRecorderCoordinator.beginRecording(_:)
        )
        button.identifier = NSUserInterfaceItemIdentifier(
            BrowserShortcutSettingsAccessibilityID.recorderPrefix + identifier
        )
        button.recordingTitle = BrowserShortcutLocalization.string(
            BrowserShortcutSettingsPresentation.typeShortcut,
            locale: locale
        )
        button.eventHandler = context.coordinator.handle
        return button
    }

    func updateNSView(
        _ button: ShortcutRecorderButton,
        context: Context
    ) {
        context.coordinator.update(
            record: record,
            reportInvalidShortcut: reportInvalidShortcut
        )
        button.restingTitle =
            shortcut?.displayString(locale: locale)
            ?? BrowserShortcutSettingsPresentation.emptyShortcutGlyph
        button.recordingTitle = BrowserShortcutLocalization.string(
            BrowserShortcutSettingsPresentation.typeShortcut,
            locale: locale
        )
        button.eventHandler = context.coordinator.handle
        button.setAccessibilityLabel(
            BrowserShortcutLocalization.string(
                BrowserShortcutSettingsPresentation
                    .recorderAccessibilityLabel(title: title),
                locale: locale
            )
        )
        button.setAccessibilityValue(
            shortcut?.displayString(locale: locale)
                ?? BrowserShortcutLocalization.string(
                    BrowserShortcutSettingsPresentation.unassigned,
                    locale: locale
                )
        )
        let help = BrowserShortcutLocalization.string(
            BrowserShortcutSettingsPresentation.recorderHelp,
            locale: locale
        )
        button.setAccessibilityHelp(help)
        button.toolTip = help
    }
}

@MainActor
final class BrowserShortcutRecorderCoordinator: NSObject {
    private var record: (BrowserShortcut?) -> Void
    private var reportInvalidShortcut: () -> Void

    init(
        record: @escaping (BrowserShortcut?) -> Void,
        reportInvalidShortcut: @escaping () -> Void
    ) {
        self.record = record
        self.reportInvalidShortcut = reportInvalidShortcut
    }

    func update(
        record: @escaping (BrowserShortcut?) -> Void,
        reportInvalidShortcut: @escaping () -> Void
    ) {
        self.record = record
        self.reportInvalidShortcut = reportInvalidShortcut
    }

    @objc func beginRecording(_ sender: ShortcutRecorderButton) {
        sender.beginRecording()
    }

    func handle(_ event: NSEvent, sender: ShortcutRecorderButton) {
        let modifiers = ShortcutModifiers(event.modifierFlags)
        if modifiers.isEmpty,
            let specialKey = ShortcutSpecialKey(keyCode: event.keyCode)
        {
            switch specialKey {
            case .escape:
                sender.endRecording()
                return
            case .delete, .forwardDelete:
                record(nil)
                sender.endRecording()
                return
            default:
                break
            }
        }

        guard let key = BrowserShortcutKey(event: event) else {
            reportInvalidShortcut()
            return
        }
        let shortcut = BrowserShortcut(key: key, modifiers: modifiers)
        guard shortcut.isValid else {
            reportInvalidShortcut()
            return
        }
        record(shortcut)
        sender.endRecording()
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var restingTitle = BrowserShortcutSettingsPresentation.emptyShortcutGlyph {
        didSet {
            guard !isRecording else { return }
            title = restingTitle
        }
    }

    var recordingTitle = BrowserShortcutLocalization.string(
        BrowserShortcutSettingsPresentation.typeShortcut,
        locale: .current
    ) {
        didSet {
            guard isRecording else { return }
            title = recordingTitle
        }
    }

    var eventHandler: ((NSEvent, ShortcutRecorderButton) -> Void)?

    private(set) var isRecording = false
    private var eventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = recordingTitle
        bezelColor = .controlAccentColor
        window?.makeFirstResponder(self)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard
                let self,
                self.isRecording,
                self.window?.isKeyWindow == true
            else {
                return event
            }
            self.eventHandler?(event, self)
            return nil
        }
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        title = restingTitle
        bezelColor = nil
        removeEventMonitor()
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            isRecording = false
            title = restingTitle
            bezelColor = nil
            removeEventMonitor()
        }
        return resigned
    }

    isolated deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}
