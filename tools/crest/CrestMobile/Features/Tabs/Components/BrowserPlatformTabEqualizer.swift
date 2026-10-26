import SwiftUI
import UIKit

/// Hosts a tab's equalizer layer in a UIKit view that takes no touches.
struct BrowserPlatformTabEqualizer: UIViewRepresentable {
    // MARK: - Variables

    let color: Color
    let isMoving: Bool
    let spectrum: BrowserAudioSpectrumFeed?

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.equalizer?.barColor = color.resolve(in: context.environment).cgColor
        view.equalizer?.isMoving = isMoving
        view.equalizer?.follow(spectrum)
    }

    static func dismantleUIView(_ view: HostView, coordinator: ()) {
        view.equalizer?.follow(nil)
    }

    // MARK: - Types

    /// A view whose own layer is the equalizer.
    final class HostView: UIView {
        override static var layerClass: AnyClass { BrowserTabEqualizerLayer.self }

        /// The backing layer, which `layerClass` makes an equalizer.
        var equalizer: BrowserTabEqualizerLayer? { layer as? BrowserTabEqualizerLayer }
    }
}
