import SwiftUI

/// The outline of a crest's plate, drawn as a path so it stays crisp at any
/// size and can be stroked, inset, and scaled — none of which a glyph mask
/// allowed.
struct BrowserSpaceCrestPlateShape: Shape {
    let backplate: CrestBackplate
    /// Scallops on a seal. Ignored by every other plate.
    var scallops = 14

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        switch backplate.kind {
        case .none:
            break
        case .circle:
            path.addEllipse(in: rect)
        case .oval:
            path.addEllipse(in: rect.insetBy(dx: w * 0.11, dy: 0))
        case .shield:
            path.move(to: point(0.06, 0.08))
            path.addLine(to: point(0.94, 0.08))
            path.addLine(to: point(0.94, 0.46))
            path.addQuadCurve(to: point(0.5, 0.98), control: point(0.94, 0.86))
            path.addQuadCurve(to: point(0.06, 0.46), control: point(0.06, 0.86))
            path.closeSubpath()
        case .frenchShield:
            path.move(to: point(0.08, 0.04))
            path.addLine(to: point(0.92, 0.04))
            path.addLine(to: point(0.92, 0.70))
            path.addQuadCurve(to: point(0.5, 0.97), control: point(0.92, 0.97))
            path.addQuadCurve(to: point(0.08, 0.70), control: point(0.08, 0.97))
            path.closeSubpath()
        case .diamond:
            path.move(to: point(0.5, 0.02))
            path.addLine(to: point(0.96, 0.5))
            path.addLine(to: point(0.5, 0.98))
            path.addLine(to: point(0.04, 0.5))
            path.closeSubpath()
        case .hexagon:
            path.addPath(Self.polygon(sides: 6, in: rect, rotation: -.pi / 2))
        case .octagon:
            path.addPath(Self.polygon(sides: 8, in: rect, rotation: .pi / 8))
        case .roundedSquare:
            path.addRoundedRect(
                in: rect.insetBy(dx: w * 0.05, dy: h * 0.05),
                cornerSize: CGSize(width: w * 0.22, height: h * 0.22),
                style: .continuous)
        case .seal:
            path.addPath(Self.scalloped(in: rect, scallops: max(6, scallops)))
        case .banner:
            path.move(to: point(0.12, 0.04))
            path.addLine(to: point(0.88, 0.04))
            path.addLine(to: point(0.88, 0.76))
            path.addLine(to: point(0.5, 0.97))
            path.addLine(to: point(0.12, 0.76))
            path.closeSubpath()
        case .badge:
            let center = point(0.5, 0.44)
            let radius = w * 0.44
            path.addArc(
                center: center, radius: radius, startAngle: .degrees(160), endAngle: .degrees(20), clockwise: false)
            path.addLine(to: point(0.5, 0.98))
            path.closeSubpath()
        }
        return path
    }

    static func polygon(sides: Int, in rect: CGRect, rotation: CGFloat) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<sides {
            let angle = rotation + CGFloat(index) / CGFloat(sides) * 2 * .pi
            let vertex = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        return path
    }

    static func scalloped(in rect: CGRect, scallops: Int) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.9
        var path = Path()
        for index in 0..<scallops {
            let start = CGFloat(index) / CGFloat(scallops) * 2 * .pi - .pi / 2
            let end = CGFloat(index + 1) / CGFloat(scallops) * 2 * .pi - .pi / 2
            let mid = (start + end) / 2
            let valley = CGPoint(x: center.x + cos(start) * inner, y: center.y + sin(start) * inner)
            let nextValley = CGPoint(x: center.x + cos(end) * inner, y: center.y + sin(end) * inner)
            let control = CGPoint(x: center.x + cos(mid) * outer * 1.08, y: center.y + sin(mid) * outer * 1.08)
            if index == 0 { path.move(to: valley) }
            path.addQuadCurve(to: nextValley, control: control)
        }
        path.closeSubpath()
        return path
    }
}
