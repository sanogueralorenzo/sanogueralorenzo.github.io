import CoreGraphics
import Foundation

enum BrowserQuickWindowLayout {
    static let defaultWidth: CGFloat = 720
    static let defaultHeight: CGFloat = 460
    static let minimumWidth: CGFloat = 600
    static let minimumHeight: CGFloat = 400
    static let maximumScreenFallbackWidth: CGFloat = 1_440
    static let maximumScreenFallbackHeight: CGFloat = 1_000
    // The page surface owns the gap below the controls through its frame inset.
    static let toolbarHeight: CGFloat = controlHeight + toolbarTopPadding
    static let controlHeight: CGFloat = BrowserChromeLayout.addressHeight
    static let minimumMacHitTarget: CGFloat = 28
    static let addressMinimumWidth: CGFloat = 220
    static let addressVerticalPadding: CGFloat = 6
    static let horizontalPadding: CGFloat = 10
    static let toolbarTopPadding: CGFloat = horizontalPadding
    static let toolbarSpacing: CGFloat = 8
    static let sourceChipHorizontalPadding: CGFloat = 9
    static let sourceChipLeadingInset: CGFloat = (controlHeight - CrestLayout.minimumHitTarget) / 2
    static let windowControlClearance: CGFloat = 92
    static let spacePickerWidth: CGFloat = 240
    static let spacePickerRowHeight: CGFloat = 38
    static let initialAddressFocusDelay: Duration = .milliseconds(120)
}
