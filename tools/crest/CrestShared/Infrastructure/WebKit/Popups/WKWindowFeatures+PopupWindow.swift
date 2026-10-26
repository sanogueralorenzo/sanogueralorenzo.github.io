import WebKit

extension WKWindowFeatures {
    // MARK: - Static Variables

    private static let wantsPopupKey = "_wantsPopup"

    // MARK: - Variables

    /// Whether the page asked for a popup window rather than a tab, as HTML's
    /// "check if a popup window is requested" decides: `popup` itself, or
    /// window features that leave the location bar and toolbar, the menu bar,
    /// resizing, the scroll bars or the status bar off, which any size or
    /// position alone does. WebKit answers it itself; one that does not is
    /// read from the features it exposes.
    var requestsPopupWindow: Bool {
        if responds(to: NSSelectorFromString(Self.wantsPopupKey)),
            let wantsPopup = value(forKey: Self.wantsPopupKey) as? Bool
        {
            return wantsPopup
        }
        let bars = [toolbarsVisibility, menuBarVisibility, statusBarVisibility, allowsResizing]
        guard (bars + [x, y, width, height]).contains(where: { $0 != nil }) else { return false }
        return bars.contains { $0?.boolValue != true }
    }
}
