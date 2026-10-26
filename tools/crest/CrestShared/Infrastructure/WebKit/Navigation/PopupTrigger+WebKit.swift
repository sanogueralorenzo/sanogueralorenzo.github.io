import WebKit

extension BrowserPopupTrigger {
    static func classify(_ navigationType: WKNavigationType) -> BrowserPopupTrigger {
        switch navigationType {
        case .linkActivated, .formSubmitted:
            .explicitUserNavigation
        case .backForward, .reload, .formResubmitted, .other:
            .scripted
        @unknown default:
            .scripted
        }
    }
}
