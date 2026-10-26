import AppKit

@MainActor
enum BrowserOnboardingWindowActivation {
    /// The window name assistive technology uses to find the wizard. The
    /// wizard draws its own chrome, so nothing displays this — but the accessibility
    /// tree still needs a name to address the window by.
    static let windowTitle = "Crest Setup"
}
