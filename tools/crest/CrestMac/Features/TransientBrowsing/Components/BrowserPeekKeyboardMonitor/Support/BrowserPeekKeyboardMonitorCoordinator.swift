@preconcurrency import AppKit

@MainActor
final class BrowserPeekKeyboardMonitorCoordinator: NSObject {
    var dismiss: () -> Void
    var windowNumber: Int?
    var installsMonitor: Bool
    private var monitor: Any?

    init(
        dismiss: @escaping () -> Void,
        installsMonitor: Bool
    ) {
        self.dismiss = dismiss
        self.installsMonitor = installsMonitor
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.installsMonitor,
                event.windowNumber == self.windowNumber,
                Self.dismisses(
                    keyCode: event.keyCode,
                    modifierFlags: BrowserKeyboardModifierFlags(
                        event.modifierFlags
                    )
                )
            else { return event }

            self.dismiss()
            return nil
        }
    }

    /// Whether a key press closes Peek: Escape, without Command, Control or
    /// Option. Return and Enter stay with the page.
    nonisolated static func dismisses(
        keyCode: UInt16,
        modifierFlags: BrowserKeyboardModifierFlags
    ) -> Bool {
        let disallowedModifiers: BrowserKeyboardModifierFlags = [
            .command,
            .control,
            .option,
        ]
        guard modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return false
        }
        return keyCode == 53
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    isolated deinit {
        stop()
    }
}
