import WebKit

/// The configuration WebKit derived from the opener. Adopting it preserves
/// the signed-in data store, user content controller, and window.opener.
struct WebKitPopup {
    let configuration: WKWebViewConfiguration
}
