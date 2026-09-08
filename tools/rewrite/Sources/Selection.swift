import AppKit
import ApplicationServices

@MainActor
enum Accessibility {
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
    static func range(_ element: AXUIElement) -> NSRange? {
        guard let value = value(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    static func fingerprint(_ element: AXUIElement) -> SelectionFingerprint? {
        guard let text = value(element, kAXSelectedTextAttribute) as? String,
              let value = value(element, kAXValueAttribute) as? String,
              let range = range(element) else { return nil }
        let fingerprint = SelectionFingerprint(value: value, range: range, text: text)
        return fingerprint.isConsistent ? fingerprint : nil
    }
}

@MainActor
final class CapturedSelection {
    let app: NSRunningApplication
    let element: AXUIElement
    let window: AXUIElement?
    let text: String
    let fingerprint: SelectionFingerprint?
    let point: NSPoint
    let supportsReplacement: Bool
    private(set) var invalidated = false
    private var observer: AXObserver?

    init(app: NSRunningApplication, element: AXUIElement, text: String) {
        self.app = app; self.element = element; self.text = text
        self.window = Accessibility.element(element, kAXWindowAttribute)
        self.fingerprint = Accessibility.fingerprint(element)
        var settable = DarwinBoolean(false)
        supportsReplacement = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue && fingerprint != nil
        point = Self.selectionPoint(element) ?? NSEvent.mouseLocation
        // A change away and back is still a changed selection. Never reset invalidated.
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, pointer in
            guard let pointer else { return }
            MainActor.assumeIsolated {
                Unmanaged<CapturedSelection>.fromOpaque(pointer).takeUnretainedValue().invalidated = true
            }
        }
        if AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created {
            observer = created
            for notification in [kAXSelectedTextChangedNotification, kAXValueChangedNotification] {
                AXObserverAddNotification(created, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
    }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }

    static func capture(sourceApp: NSRunningApplication? = nil) throws -> CapturedSelection {
        guard AXIsProcessTrusted() else {
            throw RewriteError.message("Allow Rewrite in System Settings → Privacy & Security → Accessibility, then select text and try again.")
        }
        guard let app = sourceApp ?? NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let focused = Accessibility.element(Accessibility.application(app.processIdentifier), kAXFocusedUIElementAttribute) else {
            throw RewriteError.message("Select text in an app, then press the Rewrite shortcut again.")
        }
        AXUIElementSetMessagingTimeout(focused, 1)
        guard Accessibility.value(focused, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let text = Accessibility.value(focused, kAXSelectedTextAttribute) as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RewriteError.message("No readable selection. Select text in an editable field and try again. This app may not expose its selection to Accessibility.")
        }
        guard text.utf16.count <= Editing.maximumUTF16 else {
            throw RewriteError.message("Select a shorter passage (up to 24,000 characters) and try again.")
        }
        return CapturedSelection(app: app, element: focused, text: text)
    }

    func validateForRewrite() throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw RewriteError.message("The original app is no longer in front. Select the text and try again.")
        }
        if let reason = replacementLimitation() { throw RewriteError.message(reason) }
    }

    func replacementLimitation() -> String? {
        guard supportsReplacement else { return "This app does not support direct replacement. Try a standard text field in another app." }
        guard !app.isTerminated, !invalidated, let fingerprint,
              Accessibility.fingerprint(element) == fingerprint else {
            return "The original text or selection changed. Select the text and try again."
        }
        let application = Accessibility.application(app.processIdentifier)
        guard let focused = Accessibility.element(application, kAXFocusedUIElementAttribute), CFEqual(focused, element),
              let window, let current = Accessibility.element(application, kAXFocusedWindowAttribute), CFEqual(window, current) else {
            return "The original field is no longer focused. Select the text in that field and try again."
        }
        return nil
    }

    func replace(with result: String, requireForeground: Bool = false) async throws {
        if requireForeground && NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            throw RewriteError.message("You switched apps before the rewrite finished. Return to the original app, select the text, and try again.")
        }
        if let reason = replacementLimitation() { throw RewriteError.message(reason) }
        if !requireForeground {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier || app.activate(options: []) else { throw RewriteError.message("Could not return to the original app. Select the text and try again.") }
        }
        // Activation is asynchronous. Verify the destination again after it takes effect.
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw RewriteError.message("The original app could not take focus. Select the text and try again.")
        }
        if let reason = replacementLimitation() { throw RewriteError.message(reason) }
        // Target the captured AX element directly. No global paste event, clipboard mutation,
        // selection restoration, or whole-document setter can affect an unintended field.
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, result as CFString) == .success else {
            throw RewriteError.message("This app refused replacement. Try a standard text field in another app.")
        }
        // Some web editors report success without implementing AXSelectedText writes.
        // Wait for acknowledgement, but never retry a mutation or replace the full value.
        let expected = fingerprint!.replacing(with: result)
        for _ in 0..<12 {
            if Accessibility.value(element, kAXValueAttribute) as? String == expected { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        if Accessibility.fingerprint(element) == fingerprint {
            throw RewriteError.message("This app did not apply the replacement. Try a standard text field in another app.")
        }
        throw RewriteError.message("Could not verify the replacement. Check the original field and use Undo if needed.")
    }

    func restoreFocus() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if front == ProcessInfo.processInfo.processIdentifier || front == app.processIdentifier { app.activate(options: []) }
    }

    private static func selectionPoint(_ element: AXUIElement) -> NSPoint? {
        guard let range = Accessibility.value(element, kAXSelectedTextRangeAttribute) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), !rect.isEmpty,
              let primary = NSScreen.screens.first else { return nil }
        return NSPoint(x: rect.minX, y: primary.frame.maxY - rect.maxY - 5)
    }
}

// UTF-16 matches the ranges used by macOS Accessibility and NSString, including emoji.
struct SelectionFingerprint: Equatable {
    let value: String
    let range: NSRange
    let text: String

    var isConsistent: Bool {
        let string = value as NSString
        return range.location != NSNotFound && range.location >= 0 && range.length > 0 &&
            range.location <= string.length && range.length <= string.length - range.location &&
            string.substring(with: range) == text
    }
    func replacing(with result: String) -> String { (value as NSString).replacingCharacters(in: range, with: result) }
}
