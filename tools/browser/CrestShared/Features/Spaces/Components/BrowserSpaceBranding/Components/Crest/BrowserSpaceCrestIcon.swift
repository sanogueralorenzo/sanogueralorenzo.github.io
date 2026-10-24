import SwiftUI

/// A Space's crest at any size: plate, field, band, edge, trim, and charge,
/// composed from paths and colored from the crest's own tinctures or the
/// Space's.
struct BrowserSpaceCrestIcon: View, Equatable {
    let branding: SpaceBranding
    var size: CGFloat = 44
    var rasterizesLayers = true

    /// The plate's diameter as a fraction of the icon, before ``SpaceCrest/plateScale``.
    static let plateFraction: CGFloat = 0.78

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.branding.crest == rhs.branding.crest && lhs.branding.colors == rhs.branding.colors
            && lhs.size == rhs.size && lhs.rasterizesLayers == rhs.rasterizesLayers
    }

    var body: some View {
        let crest = branding.crest
        let plate = BrowserSpaceCrestPlateShape(backplate: crest.backplate, scallops: crest.sealTeeth)
        let plateSide = size * Self.plateFraction * CGFloat(crest.plateScale)
        let plateRect = CGRect(
            x: (size - plateSide) / 2, y: (size - plateSide) / 2, width: plateSide, height: plateSide)
        ZStack {
            if crest.backplate != .none {
                BrowserSpaceCrestField(
                    division: crest.fieldDivision,
                    divisionCount: crest.divisionCount,
                    finish: crest.finish,
                    sheenAngle: crest.sheenAngle,
                    primaryColor: color(at: crest.backplateColorIndex),
                    secondaryColor: color(at: crest.secondaryFieldColorIndex)
                )
                .frame(width: plateSide, height: plateSide)
                .clipShape(plate)

                BrowserSpaceCrestOrdinaryView(
                    ordinary: crest.ordinary,
                    width: crest.ordinaryWidth,
                    plate: plate,
                    color: color(at: crest.ordinaryColorIndex),
                    size: plateSide
                )

                if crest.showsOutline {
                    plate.stroke(color(at: crest.edgeColorIndex), lineWidth: max(0.6, size * 0.012))
                        .frame(width: plateSide, height: plateSide)
                }
                if crest.edgeWidth > 0 {
                    plate
                        .stroke(
                            color(at: crest.edgeColorIndex),
                            style: StrokeStyle(
                                lineWidth: max(0.75, plateSide * 0.06 * CGFloat(crest.edgeWidth)), lineJoin: .round)
                        )
                        .frame(width: plateSide, height: plateSide)
                        .clipShape(plate)
                }
            }

            BrowserSpaceCrestTrimView(
                trim: crest.trim,
                weight: crest.trimWeight,
                detail: crest.trimDetail,
                plate: plate,
                plateRect: plateRect,
                color: color(at: crest.trimColorIndex),
                size: size
            )

            BrowserSpaceCrestChargeView(
                charge: crest.resolvedCharge,
                layout: crest.chargeLayout,
                scale: crest.chargeScale,
                offset: crest.chargeOffset,
                weight: crest.chargeWeight,
                color: color(at: crest.symbolColorIndex),
                size: size
            )
        }
        .frame(width: size, height: size)
        .modifier(BrowserSpaceCrestRasterization(enabled: rasterizesLayers))
        .modifier(BrowserSpaceCrestDepthModifier(depth: crest.depth, size: size))
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        let colors = branding.crest.layerColors(spaceColors: branding.colors)
        return colors[(0..<colors.count).contains(index) ? index : 0].color
    }
}

/// The shadow that lifts a crest off its background.
struct BrowserSpaceCrestDepthModifier: ViewModifier {
    let depth: CrestDepth
    let size: CGFloat

    func body(content: Content) -> some View {
        switch depth.kind {
        case .none:
            content
        case .soft:
            content.shadow(color: .black.opacity(0.28), radius: size * 0.04, y: size * 0.02)
        case .lifted:
            content.shadow(color: .black.opacity(0.36), radius: size * 0.1, y: size * 0.06)
        }
    }
}
