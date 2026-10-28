import AppKit

/// Crest configures its auxiliary windows by hand — Settings hides its title and the
/// setup wizard hides its whole titlebar — and a window whose title is blank reaches
/// assistive technology as an anonymous window that nothing can address by name.
/// Every hand-configured window therefore pins its own accessibility identity here
/// instead of trusting whatever the toolbar style left behind.
@MainActor
enum BrowserWindowAccessibility {
    static func pinTitle(_ title: String, on window: NSWindow) {
        if !window.styleMask.contains(.titled) {
            window.styleMask.insert(.titled)
        }
        if window.title != title {
            window.title = title
        }
        if window.accessibilityTitle() != title {
            window.setAccessibilityTitle(title)
        }
        // A window nobody can see is still announced and still reported as the
        // frontmost window, so a window that is interactable is never left
        // transparent.
        if window.alphaValue < 1 {
            window.alphaValue = 1
        }
    }
}
