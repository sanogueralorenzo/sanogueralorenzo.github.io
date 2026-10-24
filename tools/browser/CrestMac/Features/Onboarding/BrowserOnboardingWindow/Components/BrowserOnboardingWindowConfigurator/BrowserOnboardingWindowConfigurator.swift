import AppKit
import SwiftUI

struct BrowserOnboardingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = BrowserOnboardingWindowConfigurationView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BrowserOnboardingWindowConfigurationView)?.configureWindow()
    }
}
