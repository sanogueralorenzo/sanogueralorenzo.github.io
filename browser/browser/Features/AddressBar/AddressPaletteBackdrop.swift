import AppKit
import SwiftUI

struct AddressPaletteBackdrop: View {
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let canvas = BrowserBrandTheme.canvas
        return Group {
            if reduceTransparency {
                canvas
            } else {
                LinearGradient(
                    stops: [
                        .init(color: canvas.opacity(0.95), location: 0),
                        .init(color: canvas.opacity(0.93), location: 0.61),
                        .init(color: canvas.opacity(0.86), location: 0.82),
                        .init(color: canvas.opacity(0.71), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .background { AddressFocusMaterial().allowsHitTesting(false) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .accessibilityHidden(true)
    }
}

private struct AddressFocusMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
