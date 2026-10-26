import AppKit

/// macOS resolves the engine's view seam to AppKit's `NSView`.
///
/// Shared code names this type instead of either platform's view, so a page
/// engine's port compiles against whichever view its target draws with.
typealias BrowserEngineView = NSView
