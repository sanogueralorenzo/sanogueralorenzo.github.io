import SwiftUI

/// The part of a field that takes the second color.
///
/// Drawn over the primary color and clipped by the plate, so a division never
/// has to know which plate it is on.
struct BrowserSpaceCrestDivisionShape: Shape {
    let division: CrestFieldDivision
    var count = SpaceCrest.defaultDivisionCount

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        switch division.kind {
        case .plain:
            break
        case .perPale:
            path.addRect(CGRect(x: rect.midX, y: rect.minY, width: w / 2, height: h))
        case .perFess:
            path.addRect(CGRect(x: rect.minX, y: rect.midY, width: w, height: h / 2))
        case .perBend:
            path.move(to: point(1, 0))
            path.addLine(to: point(1, 1))
            path.addLine(to: point(0, 1))
            path.closeSubpath()
        case .perChevron:
            path.move(to: point(0, 0.48))
            path.addLine(to: point(0.5, 0.68))
            path.addLine(to: point(1, 0.48))
            path.addLine(to: point(1, 1))
            path.addLine(to: point(0, 1))
            path.closeSubpath()
        case .quarterly:
            path.addRect(CGRect(x: rect.midX, y: rect.minY, width: w / 2, height: h / 2))
            path.addRect(CGRect(x: rect.minX, y: rect.midY, width: w / 2, height: h / 2))
        case .perSaltire:
            path.move(to: point(0, 0))
            path.addLine(to: point(1, 0))
            path.addLine(to: point(0.5, 0.5))
            path.closeSubpath()
            path.move(to: point(0, 1))
            path.addLine(to: point(1, 1))
            path.addLine(to: point(0.5, 0.5))
            path.closeSubpath()
        case .gyronny:
            let wedges = max(2, count) * 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = max(w, h)
            for index in stride(from: 0, to: wedges, by: 2) {
                let start = CGFloat(index) / CGFloat(wedges) * 2 * .pi - .pi / 2
                let end = CGFloat(index + 1) / CGFloat(wedges) * 2 * .pi - .pi / 2
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + cos(start) * radius, y: center.y + sin(start) * radius))
                path.addLine(to: CGPoint(x: center.x + cos(end) * radius, y: center.y + sin(end) * radius))
                path.closeSubpath()
            }
        case .barry:
            let bands = max(2, count)
            let bandHeight = h / CGFloat(bands)
            for index in stride(from: 1, to: bands, by: 2) {
                path.addRect(
                    CGRect(x: rect.minX, y: rect.minY + CGFloat(index) * bandHeight, width: w, height: bandHeight))
            }
        case .paly:
            let bands = max(2, count)
            let bandWidth = w / CGFloat(bands)
            for index in stride(from: 1, to: bands, by: 2) {
                path.addRect(
                    CGRect(x: rect.minX + CGFloat(index) * bandWidth, y: rect.minY, width: bandWidth, height: h))
            }
        case .checky:
            let cells = max(2, count)
            let cellWidth = w / CGFloat(cells)
            let cellHeight = h / CGFloat(cells)
            for row in 0..<cells {
                for column in 0..<cells where (row + column) % 2 == 1 {
                    path.addRect(
                        CGRect(
                            x: rect.minX + CGFloat(column) * cellWidth, y: rect.minY + CGFloat(row) * cellHeight,
                            width: cellWidth, height: cellHeight))
                }
            }
        }
        return path
    }
}
