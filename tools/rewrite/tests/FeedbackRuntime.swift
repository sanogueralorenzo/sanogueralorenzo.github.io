import AppKit
import Carbon.HIToolbox

@main
@MainActor
final class FeedbackRuntime: NSObject, NSApplicationDelegate {
    let notice = ResultNotice()
    let shortcut = GlobalShortcut()
    static func main() {
        let app = NSApplication.shared, owner = FeedbackRuntime()
        app.delegate = owner; app.setActivationPolicy(.accessory)
        withExtendedLifetime(owner) { app.run() }
    }
    func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                let output = CommandLine.arguments[1]
                var cancelled = 0, copied = 0, pressed = 0
                notice.onClose = { cancelled += 1 }; notice.onCopy = { copied += 1 }
                let status = MenuBarStatus(); defer { status.remove() }
                let menu = status.item.menu!
                let button = status.item.button!
                precondition(button.subviews.allSatisfy { $0.isHidden }, "idle badge hidden")
                status.setRewriting(.grammar)
                precondition(menu.items.contains { !$0.isHidden && $0.title == "Rewriting… · Fix grammar" }, "menu explains active action")
                precondition(menu.items.contains { !$0.isHidden && $0.title == "Cancel Rewrite" && $0.isEnabled }, "busy menu can cancel")
                precondition(menu.items.first { $0.title == "Rewrite Selection" }?.isEnabled == false, "no second request while busy")
                let dot = button.subviews.first { !$0.isHidden }!
                precondition(dot.hitTest(.zero) == nil, "badge does not intercept menu clicks")
                let badge = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
                button.cacheDisplay(in: button.bounds, to: badge)
                try badge.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "-busy.png"))
                var menuCancelled = false; status.onCancel = { menuCancelled = true }
                menu.performActionForItem(at: menu.items.firstIndex { $0.title == "Cancel Rewrite" }!)
                precondition(menuCancelled, "menu dispatches cancellation")
                status.setRewriting(nil)
                precondition(dot.isHidden && menu.items.first { $0.title == "Rewrite Selection" }!.isEnabled, "completion or failure clears busy state")
                notice.show("The original text or selection changed. Copy the result, or select the text and start again.", result: "She went to the library yesterday.", at: NSPoint(x: 300, y: 700))
                if CommandLine.arguments.contains("--inspect") {
                    print("Inspect the fallback notice now."); fflush(stdout)
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                }
                try await Task.sleep(nanoseconds: 150_000_000)
                let view = notice.panel.contentView!
                view.layoutSubtreeIfNeeded()
                let controls = buttons(view)
                precondition(!controls.contains { $0.title == "Replace" }, "no acceptance step")
                let copyButton = controls.first { $0.title == "Copy" }!
                precondition(!copyButton.isHidden, "unapplied result can be copied")
                copyButton.performClick(nil); precondition(copied == 1, "copy dispatch")
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "-notice.png"))
                controls.first { $0.title == "Close" }!.performClick(nil)
                precondition(cancelled == 1, "notice dismissal")
                notice.show("The processor could not complete the rewrite.")
                precondition(copyButton.isHidden, "request failures have no empty result to copy")
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
                notice.closePanel()
                print("PASS busy badge, menu status/cancel, fallback notice, shortcut registration/conflict/callback")
                NSApp.terminate(nil)
            } catch { print(error.localizedDescription); exit(1) }
        }
    }
}
