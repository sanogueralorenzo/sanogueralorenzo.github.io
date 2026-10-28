import SwiftUI

/// Keeps the presses of a control that sits under the window's title bar,
/// rather than letting the window server drag the window from it
/// (`BrowserWindowTitleBarControlAreaView`). Place it behind the control, at
/// the control's size.
struct BrowserWindowTitleBarControlArea: NSViewRepresentable {
    func makeNSView(context: Context) -> BrowserWindowTitleBarControlAreaView {
        BrowserWindowTitleBarControlAreaView()
    }

    func updateNSView(_ nsView: BrowserWindowTitleBarControlAreaView, context: Context) {}
}
