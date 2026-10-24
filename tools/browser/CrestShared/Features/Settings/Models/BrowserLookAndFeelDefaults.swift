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
    static let tabs = BrowserTabAppearance()
    static let address = BrowserAddressAppearance()
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
    static func resetAll(
        appearance: BrowserDeviceAppearanceStore = .shared,
        chrome: UserDefaults = BrowserChromeAppearancePreference.defaults,
        density: UserDefaults = BrowserSidebarDensityPreference.defaults,
        folders: UserDefaults = BrowserFolderAppearancePreference.defaults
    ) {
        appearance.mode = appearanceMode
        appearance.darkSpaceDimming = darkSpaceDimming
        appearance.cornerRadius = cornerRadius
        appearance.tabs = tabs
        appearance.address = address
        appearance.surfaceMaterial = surfaceMaterial
        appearance.spaceIconSizing = spaceIconSizing
        appearance.spaceIconScale = spaceIconScale

        chrome.set(windowBorderWidth, forKey: BrowserChromeAppearancePreference.borderWidthKey)
        chrome.set(sidebarOnRight, forKey: BrowserChromeAppearancePreference.sidebarOnRightKey)

        density.set(tabScale, forKey: BrowserSidebarDensityPreference.scaleKey)
        density.set(pinColumns, forKey: BrowserSidebarDensityPreference.pinColumnsKey)
        density.set(pinsFillRow, forKey: BrowserSidebarDensityPreference.pinsFillRowKey)

        folders.set(foldersAlwaysVisible, forKey: BrowserFolderAppearancePreference.alwaysVisibleKey)
        folders.set(foldersShowTabCounts, forKey: BrowserFolderAppearancePreference.showsTabCountsKey)
        folders.set(foldersShowBorders, forKey: BrowserFolderAppearancePreference.showsBordersKey)
        folders.set(foldersIconOnly, forKey: BrowserFolderAppearancePreference.iconOnlyKey)
        folders.set(foldersTintTitle, forKey: BrowserFolderAppearancePreference.tintsTitleKey)
    }
}
