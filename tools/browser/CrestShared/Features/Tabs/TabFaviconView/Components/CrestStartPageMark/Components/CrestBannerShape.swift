import SwiftUI

struct CrestBannerShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + (rect.width * x),
                y: rect.minY + (rect.height * y)
            )
        }

        var path = Path()
        path.move(to: point(0.329, 0.186))
        path.addLine(to: point(0.671, 0.186))
        path.addQuadCurve(
            to: point(0.710, 0.225),
            control: point(0.710, 0.186)
        )
        path.addLine(to: point(0.710, 0.756))
        path.addQuadCurve(
            to: point(0.694, 0.786),
            control: point(0.710, 0.775)
        )
        path.addQuadCurve(
            to: point(0.666, 0.784),
            control: point(0.682, 0.795)
        )
        path.addLine(to: point(0.519, 0.686))
        path.addQuadCurve(
            to: point(0.481, 0.686),
            control: point(0.500, 0.673)
        )
        path.addLine(to: point(0.334, 0.784))
        path.addQuadCurve(
            to: point(0.306, 0.786),
            control: point(0.318, 0.795)
        )
        path.addQuadCurve(
            to: point(0.290, 0.756),
            control: point(0.290, 0.775)
        )
        path.addLine(to: point(0.290, 0.225))
        path.addQuadCurve(
            to: point(0.329, 0.186),
            control: point(0.290, 0.186)
        )
        path.closeSubpath()
        return path
    }
}
