import WebKit

/// Supplies the source origin for navigation-action implementations that do not
/// come from WebKit. `WKNavigationAction` has no valid public initializer, so a
/// synthetic subclass must never ask the inherited `sourceFrame` implementation
/// to read WebKit's missing internal state.
@MainActor
protocol BrowserNavigationActionSourceOriginProviding: AnyObject {
    var browserSourceOrigin: SiteOrigin? { get }
}
