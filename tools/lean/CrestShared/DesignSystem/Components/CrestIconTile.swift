import SwiftUI

/// A reusable colored symbol tile for navigation, settings, and feature identity.
struct CrestIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 30
    var symbolSize: CGFloat = 14
    var cornerRadius: CGFloat = CrestRadius.compact
    var castsShadow = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: symbolSize, weight: .semibold))
            .browserReadableForeground(over: color)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: cornerRadius))
            .shadow(
                color: color.opacity(castsShadow && !reduceTransparency ? 0.2 : 0),
                radius: castsShadow ? 5 : 0,
                y: castsShadow ? CrestSpacing.extraExtraSmall : 0
            )
    }
}

#if DEBUG
    #Preview("Sizes and colors") {
        HStack(spacing: 20) {
            CrestIconTile(systemImage: "gearshape.fill", color: .indigo)
            CrestIconTile(systemImage: "lock.shield.fill", color: .green, castsShadow: true)
            CrestIconTile(systemImage: "square.grid.2x2.fill", color: .orange, size: 48, symbolSize: 24)
        }.padding()
    }
#endif
