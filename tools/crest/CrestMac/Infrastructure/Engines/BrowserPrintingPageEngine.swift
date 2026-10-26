import AppKit

/// A page engine that prints its own view, a page at a time. A page whose
/// engine is not one prints from the PDF its engine exports.
@MainActor
protocol BrowserPrintingPageEngine: BrowserPageEngine {
    /// The engine's own print operation for its view; nil when the page
    /// prints from the PDF its engine exports.
    func printOperation(with info: NSPrintInfo) -> NSPrintOperation?
}
