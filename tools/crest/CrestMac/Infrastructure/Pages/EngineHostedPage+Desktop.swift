import Foundation

extension EngineHostedPage {
    /// The adapter a Mac window's page reaches what the engine built through:
    /// a new one over the page WebKit's binding built, or the adapter an
    /// engine the core runs directly built as its host.
    func makeDesktopAdapter() -> any BrowserPageEngineAdapter {
        if let adapter = self as? any BrowserPageEngineAdapter { return adapter }
        if let webKitPage = self as? WebKitEnginePage { return BrowserWebKitPageAdapter(page: webKitPage) }
        preconditionFailure("An engine built something other than a desktop page.")
    }
}
