/// The native surface shown for the selected tab and its current page.
enum PagePresentation: String, Sendable {
    case noSelection, startPage, nativeContent, livePage, navigationFailure, processFailure, unloaded, automaticRestore

    static func of(
        _ surface: TabSurface?, hasPage: Bool, hasNavigationFailure: Bool, hasProcessFailure: Bool,
        restoresUnloaded: Bool = false
    ) -> Self {
        guard let surface else { return .noSelection }
        if surface == .startPage { return .startPage }
        if !surface.showsPage { return .nativeContent }
        if !hasPage { return restoresUnloaded ? .automaticRestore : .unloaded }
        return hasNavigationFailure ? .navigationFailure : hasProcessFailure ? .processFailure : .livePage
    }
}
