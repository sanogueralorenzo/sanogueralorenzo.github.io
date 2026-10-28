import SwiftUI

/// A sidebar row's auxiliary-button click.
///
/// On a pointer shell that is the middle button, which closes a current tab
/// and unloads a saved one. The gesture itself lives in
/// `BrowserMiddleClickGesture`; this modifier is only the seam that lets a
/// shared row ask for the behavior without naming AppKit.
struct BrowserPlatformRowAuxiliaryClickModifier: ViewModifier {
    var perform: (@MainActor () -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let perform {
            content.browserOnMiddleClick(perform: perform)
        } else {
            content
        }
    }
}
