import CoreGraphics

/// The measurements the Settings window and its pages lay out with.
enum BrowserSettingsLayout {
    static let sidebarMinimumWidth: CGFloat = 224
    static let sidebarIdealWidth: CGFloat = 236
    static let sidebarMaximumWidth: CGFloat = 260
    static let sidebarIconSize: CGFloat = 24
    static let sidebarRowMinimumHeight: CGFloat = 34
    static let showsSidebarSubtitles = false
    static let pageIconSize: CGFloat = 48
    static let maximumReadableContentWidth: CGFloat = 700
    /// The width of a settings page's one column of grouped rows.
    static let formColumnWidth: CGFloat = 640
    /// The least space kept between the column and the page's edges.
    static let formMinimumInset: CGFloat = 12

    /// The margin that centres the settings column in a page of the given
    /// width, and keeps at least the minimum on each side of a narrow one.
    static func formInset(for width: CGFloat, columnWidth: CGFloat = formColumnWidth) -> CGFloat {
        max(formMinimumInset, (width - columnWidth) / 2)
    }
}
