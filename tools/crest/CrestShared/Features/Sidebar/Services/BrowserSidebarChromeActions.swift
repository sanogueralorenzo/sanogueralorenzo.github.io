import Foundation

/// Native presentation routes supplied by the sidebar's platform shell.
/// Optional routes are omitted when that shell reaches the feature elsewhere.
@MainActor
struct BrowserSidebarChromeActions {
    /// Opens the Space's own settings, wherever this shell keeps them.
    let presentSpaceSettings: (BrowserSpaceRuntimeAssignment) -> Void

    /// Brings the selected Space's history on screen, inline or as a sheet.
    let presentHistory: () -> Void

    /// Brings the selected Space's archive on screen. Absent where the archive
    /// is one of the inline utility surfaces rather than a sheet of its own.
    let presentArchive: (() -> Void)?

    /// Brings the selected Space's downloads on screen, under the same rule as
    /// `presentArchive`.
    let presentDownloads: (() -> Void)?

    /// Adds a Space and opens it for editing. Absent where the sidebar offers
    /// no create affordance of its own.
    let createSpace: (() -> Void)?

    /// Deletes the captured Space directly, through the platform's profile cleanup.
    let deleteSpace: ((BrowserSpaceRuntimeAssignment) -> Void)?

    init(
        presentSpaceSettings: @escaping (BrowserSpaceRuntimeAssignment) -> Void,
        presentHistory: @escaping () -> Void,
        presentArchive: (() -> Void)? = nil,
        presentDownloads: (() -> Void)? = nil,
        createSpace: (() -> Void)? = nil,
        deleteSpace: ((BrowserSpaceRuntimeAssignment) -> Void)? = nil
    ) {
        self.presentSpaceSettings = presentSpaceSettings
        self.presentHistory = presentHistory
        self.presentArchive = presentArchive
        self.presentDownloads = presentDownloads
        self.createSpace = createSpace
        self.deleteSpace = deleteSpace
    }
}
