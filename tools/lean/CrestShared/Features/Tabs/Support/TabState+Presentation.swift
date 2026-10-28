import Foundation

extension TabState {
    /// The name the tab surfaces show, in the person's language, as
    /// `TabStateModel.shownTitle` reads it.
    var shownTitle: String {
        guard let nativeView, BrowserShownTitle.resolve(customTitle) == nil else { return displayTitle }
        return String(localized: nativeView.title)
    }
}
