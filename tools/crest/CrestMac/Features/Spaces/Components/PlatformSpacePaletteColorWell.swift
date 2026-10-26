import AppKit
import SwiftUI

/// A full-size native color well keeps the system picker, keyboard support,
/// and color drag/drop while allowing the swatch to fill its palette column.
struct PlatformSpacePaletteColorWell: NSViewRepresentable {
    @Binding var selection: Color

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.colorWellStyle = .minimal
        well.supportsAlpha = false
        well.target = context.coordinator
        well.action = #selector(Coordinator.changeColor(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.selection = $selection
        let color = NSColor(selection)
        if well.color != color { well.color = color }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSColorWell, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: proposal.height ?? 56)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) {
        well.deactivate()
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Color>
        init(selection: Binding<Color>) { self.selection = selection }
        @objc func changeColor(_ sender: NSColorWell) {
            selection.wrappedValue = Color(nsColor: sender.color)
        }
    }
}

#if DEBUG
    #Preview("Choose a color") {
        @Previewable @State var color: Color = .indigo
        PlatformSpacePaletteColorWell(selection: $color).padding()
    }
#endif
