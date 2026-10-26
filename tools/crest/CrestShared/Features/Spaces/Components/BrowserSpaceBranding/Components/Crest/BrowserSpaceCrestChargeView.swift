import SwiftUI

/// One figure, drawn however the charge asks: a system symbol, an emoji, or a
/// monogram.
struct BrowserSpaceCrestChargeGlyph: View {
    let charge: CrestCharge
    let pointSize: CGFloat
    let weight: CrestChargeWeight
    let color: Color

    var body: some View {
        switch charge.kind.kind {
        case .heraldic:
            let symbol = charge.symbol ?? .fallback
            if let assetName = symbol.assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: pointSize * 1.25, height: pointSize * 1.25)
                    .foregroundStyle(color)
            } else {
                Image(systemName: symbol.systemImage)
                    .font(.system(size: pointSize, weight: fontWeight))
                    .foregroundStyle(color)
            }
        case .system:
            Image(systemName: charge.text ?? "")
                .font(.system(size: pointSize, weight: fontWeight))
                .foregroundStyle(color)
        case .emoji:
            Text(charge.text ?? "")
                .font(.system(size: pointSize * 1.05))
        case .monogram:
            let letters = charge.text ?? ""
            Text(letters)
                .font(
                    .system(
                        size: pointSize * (letters.count > 1 ? 0.92 : 1.15), weight: fontWeight,
                        design: (charge.style ?? .serif) == .serif ? .serif : .default)
                )
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        case .none:
            EmptyView()
        }
    }

    private var fontWeight: Font.Weight {
        switch weight.kind {
        case .light: .medium
        case .regular: .semibold
        case .bold: .bold
        }
    }
}

/// The figures arranged on the field.
struct BrowserSpaceCrestChargeView: View {
    let charge: CrestCharge
    let layout: CrestChargeLayout
    var scale: Double = 1
    var offset: Double = 0
    var weight: CrestChargeWeight = .bold
    let color: Color
    let size: CGFloat

    var body: some View {
        arrangement
            .offset(y: size * CGFloat(offset))
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var arrangement: some View {
        switch layout.kind {
        case .single:
            glyph(0.31)
        case .paired:
            HStack(spacing: size * 0.07) {
                glyph(0.22)
                glyph(0.22)
            }
        case .trio:
            VStack(spacing: -size * 0.03) {
                glyph(0.18)
                HStack(spacing: size * 0.07) {
                    glyph(0.18)
                    glyph(0.18)
                }
            }
        case .quad:
            VStack(spacing: size * 0.02) {
                HStack(spacing: size * 0.08) {
                    glyph(0.17)
                    glyph(0.17)
                }
                HStack(spacing: size * 0.08) {
                    glyph(0.17)
                    glyph(0.17)
                }
            }
        case .ring:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    let angle = CGFloat(index) / 5 * 2 * .pi - .pi / 2
                    glyph(0.13)
                        .offset(x: cos(angle) * size * 0.2, y: sin(angle) * size * 0.2)
                }
            }
        }
    }

    private func glyph(_ baseScale: CGFloat) -> some View {
        BrowserSpaceCrestChargeGlyph(
            charge: charge, pointSize: size * baseScale * CGFloat(scale), weight: weight, color: color)
    }
}
