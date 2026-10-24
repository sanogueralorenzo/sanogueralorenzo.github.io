import SwiftUI

/// A band laid across the field, as a fill path clipped by the plate.
///
/// Bands are built by stroking their centre lines, so one width parameter
/// drives every one of them and a chevron is a true chevron rather than a
/// glyph standing in for one.
struct BrowserSpaceCrestOrdinaryPath: Shape {
    let ordinary: CrestOrdinary
    var width: Double = 1

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let band = min(w, h) * 0.17 * CGFloat(width)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        func stroked(_ build: (inout Path) -> Void) -> Path {
            var line = Path()
            build(&line)
            return line.strokedPath(StrokeStyle(lineWidth: band, lineCap: .butt, lineJoin: .miter))
        }
        switch ordinary.kind {
        case .none:
            return Path()
        case .pale:
            return Path(CGRect(x: rect.midX - band / 2, y: rect.minY, width: band, height: h))
        case .fess:
            return Path(CGRect(x: rect.minX, y: rect.midY - band / 2, width: w, height: band))
        case .bend:
            return stroked {
                $0.move(to: point(-0.1, -0.1))
                $0.addLine(to: point(1.1, 1.1))
            }
        case .chevron:
            return stroked {
                $0.move(to: point(0.04, 0.78))
                $0.addLine(to: point(0.5, 0.34))
                $0.addLine(to: point(0.96, 0.78))
            }
        case .cross:
            var path = Path(CGRect(x: rect.midX - band / 2, y: rect.minY, width: band, height: h))
            path.addRect(CGRect(x: rect.minX, y: rect.midY - band / 2, width: w, height: band))
            return path
        case .saltire:
            return stroked {
                $0.move(to: point(-0.1, -0.1))
                $0.addLine(to: point(1.1, 1.1))
                $0.move(to: point(1.1, -0.1))
                $0.addLine(to: point(-0.1, 1.1))
            }
        case .chief:
            return Path(CGRect(x: rect.minX, y: rect.minY, width: w, height: band * 1.4))
        case .bordure:
            // Drawn by the ordinary view as an inset stroke of the plate itself.
            return Path()
        case .pall:
            return stroked {
                $0.move(to: point(0.02, 0.02))
                $0.addLine(to: point(0.5, 0.5))
                $0.move(to: point(0.98, 0.02))
                $0.addLine(to: point(0.5, 0.5))
                $0.move(to: point(0.5, 0.5))
                $0.addLine(to: point(0.5, 1.02))
            }
        case .pile:
            var path = Path()
            let halfWidth = 0.28 * CGFloat(width)
            path.move(to: point(0.5 - halfWidth, -0.02))
            path.addLine(to: point(0.5 + halfWidth, -0.02))
            path.addLine(to: point(0.5, 0.8))
            path.closeSubpath()
            return path
        case .canton:
            let side = min(w, h) * 0.36 * CGFloat(width)
            return Path(CGRect(x: rect.minX, y: rect.minY, width: side, height: side))
        case .roundel:
            let diameter = min(w, h) * 0.34 * CGFloat(width)
            return Path(
                ellipseIn: CGRect(
                    x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter))
        }
    }

    /// The bordure's stroke width for a plate of the given size.
    static func bordureWidth(size: CGFloat, width: Double) -> CGFloat {
        size * 0.09 * CGFloat(width)
    }
}
