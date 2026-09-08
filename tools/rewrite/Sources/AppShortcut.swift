import AppKit
import Carbon.HIToolbox

@MainActor
final class AppShortcut {
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let pointer else { return noErr }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<AppShortcut>.fromOpaque(pointer).takeUnretainedValue()
                var id = EventHotKeyID()
                guard owner.hotKey != nil, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                      id.signature == 0x52575254 else { return OSStatus(eventNotHandledErr) }
                owner.onPress?(); return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register() -> Bool {
        guard handler != nil else { return false }
        if hotKey != nil { return true }
        return RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(optionKey), EventHotKeyID(signature: 0x52575254, id: 1), GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    deinit { if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) } }
}
