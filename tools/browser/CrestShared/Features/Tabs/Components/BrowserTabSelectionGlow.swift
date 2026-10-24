import SwiftUI

/// The selected tab's outer glow. It slides under the layer above it — the
/// address field, the extension strip — rather than containers reserving its
/// outset as empty space; only a clipping edge with nothing over it needs the
/// outset inside its bounds, so the blur can fade before reaching it.
struct BrowserTabSelectionGlow: View {
    static let outset: CGFloat = 12

    let cornerRadius: CGFloat
    let color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { geometry in
            let tabBounds = CGRect(origin: CGPoint(x: Self.outset, y: Self.outset), size: geometry.size)
            let canvasBounds = tabBounds.insetBy(dx: -Self.outset, dy: -Self.outset)
            shape
                .fill(color)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .blur(radius: 5)
                .padding(Self.outset)
                .mask {
                    Path { path in
                        path.addRect(canvasBounds)
                        path.addPath(shape.path(in: tabBounds))
                    }
                    .fill(style: FillStyle(eoFill: true))
                }
                .offset(x: -Self.outset, y: -Self.outset)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Pinned glow at the clipping edge") {
        @Previewable @State var strength = 0.75
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                ForEach(0..<4) { index in
                    Image(systemName: index == 2 ? "globe" : "star.fill")
                        .frame(width: 47, height: 47)
                        .background(.orange.opacity(0.15), in: .capsule)
                        .overlay { Capsule().strokeBorder(index == 2 ? .orange : .clear, lineWidth: 2) }
                        .background {
                            if index == 2 {
                                BrowserTabSelectionGlow(cornerRadius: 40, color: .orange.opacity(strength * 0.6))
                            }
                        }
                }
            }
            .padding(BrowserTabSelectionGlow.outset)
            .clipped()

            Slider(value: $strength, in: 0...1) { Text("Glow") }
        }
        .padding()
        .frame(width: 300)
    }
#endif
