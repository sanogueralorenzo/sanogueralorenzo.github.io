import AppKit
import Carbon.HIToolbox

@main
@MainActor
final class PreviewRuntime: NSObject, NSApplicationDelegate {
    let preview = Preview()
    let shortcut = GlobalShortcut()
    static func main() {
        let app = NSApplication.shared, owner = PreviewRuntime()
        app.delegate = owner; app.setActivationPolicy(.accessory)
        withExtendedLifetime(owner) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/rewrite-preview.png"
                var replaced = 0, cancelled = 0, pressed = 0
                preview.onReplace = { replaced += 1 }; preview.onCancel = { cancelled += 1 }
                let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: preview.panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
                let escapeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: preview.panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
                preview.processing(action: .grammar, original: SelectionRuntimeSource.source, point: NSPoint(x: 300, y: 700), provider: "Codex CLI")
                _ = preview.panel.performKeyEquivalent(with: returnKey)
                precondition(replaced == 0, "Return must not replace during processing")
                _ = preview.panel.performKeyEquivalent(with: escapeKey)
                precondition(cancelled == 1, "Escape cancels processing")
                preview.showResult("She went to the library yesterday.", limitation: nil)
                try await Task.sleep(nanoseconds: 100_000_000)
                let view = preview.panel.contentView!
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render preview") }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
                _ = preview.panel.performKeyEquivalent(with: returnKey)
                precondition(replaced == 1, "Return replaces from preview")
                preview.limitation("The selection changed. Copy the result or start again.")
                _ = preview.panel.performKeyEquivalent(with: returnKey)
                precondition(replaced == 1, "Return cannot bypass a disabled Replace button")
                _ = preview.panel.performKeyEquivalent(with: escapeKey)
                precondition(cancelled == 2, "Escape cancels the result preview")
                shortcut.onPress = { pressed += 1 }
                let testShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "test")
                precondition(shortcut.register(testShortcut), "Hotkey registration")
                let duplicate = GlobalShortcut()
                precondition(!duplicate.register(testShortcut), "Conflicting hotkey rejected")
                var event: EventRef?
                CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeUserEvent), &event)
                var id = EventHotKeyID(signature: 0x52575254, id: 1)
                SetEventParameter(event!, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id)
                SendEventToEventTarget(event!, GetApplicationEventTarget()); ReleaseEvent(event!)
                precondition(pressed == 1, "Carbon callback dispatch")
                preview.close()
                print("PASS native preview rendering, Return/Escape, disabled replacement, shortcut registration/conflict/callback")
                NSApp.terminate(nil)
            } catch { print(error.localizedDescription); exit(1) }
        }
    }
}
enum SelectionRuntimeSource { static let source = "She go to the library yesterday." }
