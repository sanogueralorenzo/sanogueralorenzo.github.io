import Foundation

/// What a macOS page surface shows for a tab, from the page its pool holds.
extension PagePresentation {
    // MARK: - Actions - Presenting

    /// What a surface shows for a tab whose surface is `surface`, or for no
    /// tab, drawing `page` when the pool holds one.
    @MainActor
    static func of(_ surface: TabSurface?, page: BrowserPage?) -> PagePresentation {
        of(
            surface, hasPage: page != nil, hasNavigationFailure: page?.live.failure != nil,
            hasProcessFailure: page?.webContentFailureMessage != nil)
    }
}
