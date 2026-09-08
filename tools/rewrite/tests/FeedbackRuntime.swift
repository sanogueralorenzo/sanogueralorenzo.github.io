import AppKit
import Carbon.HIToolbox

@main
@MainActor
final class FeedbackRuntime: NSObject, NSApplicationDelegate {
    let shortcut = GlobalShortcut()
    static func main() {
        let app = NSApplication.shared, owner = FeedbackRuntime()
        app.delegate = owner; app.setActivationPolicy(.accessory)
        withExtendedLifetime(owner) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                let output = CommandLine.arguments[1]
                var pressed = 0
                let status = MenuBarStatus(); defer { status.remove() }
                let menu = status.item.menu!
                let button = status.item.button!
                precondition(button.subviews.allSatisfy { $0.isHidden }, "idle badge hidden")
                status.setRewriting(.grammar)
                precondition(menu.items.contains { !$0.isHidden && $0.title == "Rewriting… · Fix grammar" }, "menu explains active action")
                precondition(menu.items.contains { !$0.isHidden && $0.title == "Cancel Rewrite" && $0.isEnabled }, "busy menu can cancel")
                precondition(menu.items.first { $0.title == "Rewrite" }?.isEnabled == false, "no second request while busy")
                let dot = button.subviews.first { !$0.isHidden }!
                precondition(dot.hitTest(.zero) == nil, "badge does not intercept menu clicks")
                let badge = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
                button.cacheDisplay(in: button.bounds, to: badge)
                try badge.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "-busy.png"))
                var menuCancelled = false; status.onCancel = { menuCancelled = true }
                menu.performActionForItem(at: menu.items.firstIndex { $0.title == "Cancel Rewrite" }!)
                precondition(menuCancelled, "menu dispatches cancellation")
                status.setRewriting(nil)
                precondition(dot.isHidden && menu.items.first { $0.title == "Rewrite" }!.isEnabled, "completion or failure clears busy state")
                let windows = NSApp.windows.count
                status.showError("The selection changed. Select the text and try again.")
                precondition(NSApp.windows.count == windows, "errors do not open windows")
                precondition(menu.items.contains { !$0.isHidden && $0.title == "Rewrite needs attention" }, "errors are shown in menu bar")
                precondition(menu.items.contains { !$0.isHidden && $0.view != nil }, "menu includes error detail")
                status.setRewriting(.shorter)
                precondition(menu.items.filter { $0.view != nil }.allSatisfy { $0.isHidden }, "new request clears error detail")
                status.setRewriting(nil)
                precondition(Shortcut.standard.modifiers == UInt32(optionKey) && Shortcut.standard.keyCode == UInt32(kVK_ANSI_R), "Option-R opens Rewrite")
                let legacy = Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey | shiftKey), label: "⌥⇧R")
                precondition(legacy.migratingLegacyShortcut == .standard, "old shortcut migrates")
                let custom = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey), label: "⌃T")
                precondition(custom.migratingLegacyShortcut == custom, "custom shortcut preserved")
                let actions = ActionMenu()
                var choices: [EditAction] = []
                actions.onChoose = { choices.append($0) }
                let codes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6]
                for index in 0..<6 {
                    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0, context: nil,
                        characters: ["¡", "™", "£", "¢", "∞", "§"][index], charactersIgnoringModifiers: String(index + 1), isARepeat: false, keyCode: UInt16(codes[index]))!
                    precondition(actions.menu.performKeyEquivalent(with: event), "Option-number activates menu action")
                }
                precondition(choices == EditAction.allCases, "Option-1 through Option-6 choose the six styles in order")
                if CommandLine.arguments.contains("--menu") {
                    choices.removeAll()
                    let window = NSWindow(contentRect: NSRect(x: 280, y: 300, width: 320, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
                    window.title = "Rewrite keyboard test"; window.isReleasedWhenClosed = false
                    NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
                    print("Choose Fix grammar with Option-1 in the menu now."); fflush(stdout)
                    let picked = actions.menu.popUp(positioning: actions.menu.items.first, at: NSPoint(x: 300, y: 600), in: nil)
                    precondition(picked && choices == [.grammar], "live popup Option-1 dispatch")
                    window.orderOut(nil)
                }
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
                print("PASS busy badge, menu status/cancel, window-free errors, Option-1 through Option-6, shortcut migration/registration/conflict/callback")
                NSApp.terminate(nil)
            } catch { print(error.localizedDescription); exit(1) }
        }
    }
}
