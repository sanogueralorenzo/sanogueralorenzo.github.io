import AppKit
import SwiftUI

/// Hosts a tab's equalizer layer in an AppKit view that takes no events.
struct BrowserPlatformTabEqualizer: NSViewRepresentable {
    // MARK: - Variables

    let color: Color
    let isMoving: Bool
    let spectrum: BrowserAudioSpectrumFeed?

    func makeNSView(context: Context) -> HostView {
        HostView()
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.equalizer.barColor = color.resolve(in: context.environment).cgColor
        view.equalizer.isMoving = isMoving
        view.equalizer.follow(spectrum)
    }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
        view.equalizer.follow(nil)
    }

    // MARK: - Types

    /// A layer-hosting view: the equalizer is its layer, and clicks pass
    /// through to the tab beneath.
    final class HostView: NSView {
        let equalizer = BrowserTabEqualizerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            layer = equalizer
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
