import Foundation

/// Whether the sidebar hover area stays live while a page shows alone in full
/// screen, so the pointer at the window's edge floats the sidebar over it.
enum SidebarFullscreenRevealPreference {
    static let key = "crest.appearance.sidebar-fullscreen-reveal"
    static let defaultValue = false
}
