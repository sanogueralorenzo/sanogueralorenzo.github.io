import SwiftUI

/// What frames the plate: outlines that follow its shape, laurels, rays, beads.
///
/// Trims that follow the plate are strokes of the plate's own path drawn a
/// little larger than the plate, so they fit a shield as well as a circle.
struct BrowserSpaceCrestTrimView: View {
    let trim: CrestTrim
    var weight: Double = 1
    var detail = SpaceCrest.defaultTrimDetail
    let plate: BrowserSpaceCrestPlateShape
    /// The plate's own frame within the icon.
    let plateRect: CGRect
    let color: Color
    let size: CGFloat

    private var lineWidth: CGFloat { max(0.75, size * 0.032 * CGFloat(weight)) }

    @ViewBuilder
    var body: some View {
        switch trim.kind {
        case .none:
            EmptyView()
        case .shield:
            outline(scale: 1.12, lineWidth: lineWidth * 1.15)
        case .line:
            outline(scale: 1.1, lineWidth: lineWidth * 0.8)
        case .doubleLine, .doubleRing:
            ZStack {
                outline(scale: 1.09, lineWidth: lineWidth * 0.8)
                outline(scale: 1.2, lineWidth: lineWidth * 0.6)
            }
        case .seal:
            BrowserSpaceCrestPlateShape(backplate: .seal, scallops: max(8, detail))
                .stroke(color, lineWidth: lineWidth * 0.8)
                .frame(width: plateRect.width * 1.14, height: plateRect.height * 1.14)
        case .laurel:
            HStack(spacing: size * 0.26) {
                Image(systemName: "laurel.leading")
                Image(systemName: "laurel.trailing")
            }
            .font(.system(size: size * 0.5, weight: weight > 1.3 ? .bold : .semibold))
            .foregroundStyle(color)
        case .sunburst:
            BrowserSpaceCrestRayShape(
                rays: max(6, detail), innerRadius: 0.41, outerRadius: 0.5, thickness: 0.35 * weight
            )
            .fill(color)
            .frame(width: size, height: size)
        case .beaded:
            BrowserSpaceCrestBeadShape(beads: max(6, detail) * 2, radius: 0.455, beadRadius: 0.018 * weight)
                .fill(color)
                .frame(width: size, height: size)
        }
    }

    private func outline(scale: CGFloat, lineWidth: CGFloat) -> some View {
        plate
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            .frame(width: plateRect.width * scale, height: plateRect.height * scale)
    }
}

/// Rays around a centre, as a sunburst.
struct BrowserSpaceCrestRayShape: Shape {
    let rays: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    /// The ray's half-width at its base as a fraction of the gap between rays.
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let unit = min(rect.width, rect.height)
        var path = Path()
        let step = 2 * CGFloat.pi / CGFloat(rays)
        for index in 0..<rays {
            let angle = CGFloat(index) * step - .pi / 2
            let spread = step * min(0.45, thickness) / 2
            let base1 = CGPoint(
                x: center.x + cos(angle - spread) * unit * innerRadius,
                y: center.y + sin(angle - spread) * unit * innerRadius)
            let base2 = CGPoint(
                x: center.x + cos(angle + spread) * unit * innerRadius,
                y: center.y + sin(angle + spread) * unit * innerRadius)
            let tip = CGPoint(
                x: center.x + cos(angle) * unit * outerRadius, y: center.y + sin(angle) * unit * outerRadius)
            path.move(to: base1)
            path.addLine(to: tip)
            path.addLine(to: base2)
            path.closeSubpath()
        }
        return path
    }
}

/// Dots around a centre, as a beaded border.
struct BrowserSpaceCrestBeadShape: Shape {
    let beads: Int
    let radius: CGFloat
    let beadRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let unit = min(rect.width, rect.height)
        var path = Path()
        for index in 0..<beads {
            let angle = CGFloat(index) / CGFloat(beads) * 2 * .pi - .pi / 2
            let bead = CGPoint(x: center.x + cos(angle) * unit * radius, y: center.y + sin(angle) * unit * radius)
            let diameter = unit * beadRadius * 2
            path.addEllipse(
                in: CGRect(x: bead.x - diameter / 2, y: bead.y - diameter / 2, width: diameter, height: diameter))
        }
        return path
    }
}
