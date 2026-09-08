import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    var migratingLegacyShortcut: Shortcut {
        keyCode == UInt32(kVK_ANSI_R) && modifiers == UInt32(optionKey | shiftKey) ? .standard : self
    }
    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey), label: "⌥R")
}

@MainActor
final class GlobalShortcut {
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let pointer else { return noErr }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalShortcut>.fromOpaque(pointer).takeUnretainedValue()
                var id = EventHotKeyID()
                guard owner.hotKey != nil, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == 0x52575254 else { return OSStatus(eventNotHandledErr) }
                owner.onPress?(); return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcut: Shortcut) -> Bool {
        var next: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x52575254, id: 1), GetApplicationEventTarget(), 0, &next)
        guard status == noErr else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = next; return true
    }
    deinit { if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) } }
}

@MainActor
final class ShortcutRecorder: NSButton {
    var onRecord: ((Shortcut) -> Bool)?
    var shortcut = Shortcut.standard { didSet { title = shortcut.label } }
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { record() }
    func record() { recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { if event.keyCode == 49 { record() } else { super.keyDown(with: event) }; return }
        if event.keyCode == 53 { recording = false; title = shortcut.label; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1, key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { NSSound.beep(); return }
        var modifiers: UInt32 = 0, label = ""
        for (flag, carbon, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { modifiers |= UInt32(carbon); label += symbol }
        }
        let next = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label + key)
        if next == shortcut || onRecord?(next) == true { shortcut = next; recording = false } else { title = "In use. Try another…" }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }; return super.performKeyEquivalent(with: event)
    }
}
