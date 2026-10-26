import Foundation

extension LayoutInspector {
    /// WebKit's inspector lays itself out beside the page.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        InspectorLayout(inspector: nil, page: nil)
    }
}
