import AppKit
import SwiftUI

final class BrowserPeekWindowTrackingView: NSView {
    var onWindowChange: ((Int?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window?.windowNumber)
    }
}
