import AppKit
import ApplicationServices

@MainActor
enum Accessibility {
    static func openSettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return app
    }
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

@MainActor
enum SelectedText {
    static func read() throws -> String {
        guard AXIsProcessTrusted() else {
            throw RewriteError.accessibilityPermission
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let focused = Accessibility.element(Accessibility.application(app.processIdentifier), kAXFocusedUIElementAttribute) else {
            throw RewriteError.message("Select text in an app, then press the Rewrite shortcut again.")
        }
        AXUIElementSetMessagingTimeout(focused, 1)
        guard Accessibility.value(focused, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let text = Accessibility.value(focused, kAXSelectedTextAttribute) as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RewriteError.message("No readable selection. Select text and try again. This app may not expose its selection to Accessibility.")
        }
        guard text.utf16.count <= Editing.maximumUTF16 else {
            throw RewriteError.message("Select a shorter passage (up to 24,000 characters) and try again.")
        }
        return text
    }
}
