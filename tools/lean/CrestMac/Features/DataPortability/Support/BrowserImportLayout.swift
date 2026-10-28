import SwiftUI

/// Spacing shared by the importer selection, review, and footer.
enum BrowserImportLayout {
    // MARK: - Static Variables

    static let inset: CGFloat = 40
    static let headlineSize: CGFloat = 36
    static let pageInset: CGFloat = 120
    static let wideStageWidth: CGFloat = 1440

    // MARK: - Actions - Layout

    static func pageInset(for width: CGFloat) -> CGFloat { width >= wideStageWidth ? pageInset : inset }
}
