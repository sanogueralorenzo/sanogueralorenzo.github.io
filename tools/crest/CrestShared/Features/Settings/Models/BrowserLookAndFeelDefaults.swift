import Foundation

/// Every value the Look and Feel pane calls "unchanged", in one place.
///
/// The pane's rows, its group resets, and its stores all read the same catalog,
/// so a default can no longer drift between the `@AppStorage` declaration that
/// seeds a control and the migration code that seeds the store.
enum BrowserLookAndFeelDefaults {
    static let appearanceMode = BrowserAppearanceMode.standard
    static let darkSpaceDimming = 0.0
    static let windowBorderWidth = BrowserChromeAppearance.defaultBorderWidth
    static let sidebarOnRight = false
    static let surfaceMaterial = CrestSurfaceMaterial.standard
    static let cornerRadius: Double = 10
    static let tabScale: Double = 1
    static let pinColumns = 0
    static let pinsFillRow = false
    static let spaceIconSizing = BrowserSpaceIconSizing.standard
    static let spaceIconScale: Double = 1
    /// A new device's tab appearance, made fresh each time so a reset never
    /// shares the one instance it puts back.
    @MainActor static var tabs: BrowserTabAppearance { BrowserTabAppearance() }
    /// A new device's address field appearance, made fresh as ``tabs`` is.
    @MainActor static var address: BrowserAddressAppearance { BrowserAddressAppearance() }
    static let foldersAlwaysVisible = false
    static let foldersShowTabCounts = true
    static let foldersShowBorders = true
    static let foldersIconOnly = false
    static let foldersTintTitle = false

    /// Puts every device-wide appearance choice this pane owns back.
    ///
    /// Platform-only choices — window transparency, Space page motion, and the
    /// app icon — belong to the shell that offers them and are reset alongside
    /// this from ``BrowserLookAndFeelResetFooter``.
    @MainActor
    static func resetAll(appearance: BrowserDeviceAppearanceStore = .shared) {
        appearance.mode = appearanceMode
        appearance.darkSpaceDimming = darkSpaceDimming
        appearance.cornerRadius = cornerRadius
        appearance.tabs = tabs
        appearance.address = address
        appearance.surfaceMaterial = surfaceMaterial
        appearance.spaceIconSizing = spaceIconSizing
        appearance.spaceIconScale = spaceIconScale
        appearance.windowBorderWidth = windowBorderWidth
        appearance.sidebarOnRight = sidebarOnRight
        appearance.tabScale = tabScale
        appearance.pinColumns = pinColumns
        appearance.pinsFillRow = pinsFillRow
        appearance.foldersAlwaysVisible = foldersAlwaysVisible
        appearance.foldersShowTabCounts = foldersShowTabCounts
        appearance.foldersShowBorders = foldersShowBorders
        appearance.foldersIconOnly = foldersIconOnly
        appearance.foldersTintTitle = foldersTintTitle
        appearance.saveNow()
    }
}
