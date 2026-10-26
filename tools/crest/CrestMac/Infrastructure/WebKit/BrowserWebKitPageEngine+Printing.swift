import AppKit
import WebKit

extension BrowserWebKitPageEngine: BrowserPrintingPageEngine {
    /// WebKit prints the web view itself, a page at a time.
    func printOperation(with info: NSPrintInfo) -> NSPrintOperation? {
        webView.printOperation(with: info)
    }
}
