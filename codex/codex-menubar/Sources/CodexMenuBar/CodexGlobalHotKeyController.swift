import Carbon
import Foundation

@MainActor
final class CodexGlobalHotKeyController {
  private static let signature: OSType = 0x4344_5848  // CDXH
  private static let hotKeyID: UInt32 = 1
  private static let cKeyCode: UInt32 = 8
  private static let modifiers: UInt32 = UInt32(controlKey | optionKey)

  private var eventHandlerRef: EventHandlerRef?
  private var hotKeyRef: EventHotKeyRef?
  private let action: @MainActor () -> Void

  init(action: @escaping @MainActor () -> Void) {
    self.action = action
  }

  func register() throws {
    unregister()

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, eventRef, userData in
        guard
          let userData,
          let eventRef
        else {
          return noErr
        }

        let controller = Unmanaged<CodexGlobalHotKeyController>
          .fromOpaque(userData)
          .takeUnretainedValue()
        controller.handleHotKeyEvent(eventRef)
        return noErr
      },
      1,
      &eventType,
      selfPointer,
      &eventHandlerRef
    )

    guard installStatus == noErr else {
      throw CodexCoreCLIClient.Error(message: "Failed to install global shortcut handler.")
    }

    let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
    let registerStatus = RegisterEventHotKey(
      Self.cKeyCode,
      Self.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    guard registerStatus == noErr else {
      unregister()
      throw CodexCoreCLIClient.Error(
        message: "Failed to register global shortcut Control-Option-C.")
    }
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }

    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
      self.eventHandlerRef = nil
    }
  }

  private func handleHotKeyEvent(_ eventRef: EventRef) {
    var hotKeyID = EventHotKeyID()
    let status = withUnsafeMutablePointer(to: &hotKeyID) { pointer in
      GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        pointer
      )
    }

    guard status == noErr, hotKeyID.signature == Self.signature, hotKeyID.id == Self.hotKeyID else {
      return
    }

    action()
  }
}
