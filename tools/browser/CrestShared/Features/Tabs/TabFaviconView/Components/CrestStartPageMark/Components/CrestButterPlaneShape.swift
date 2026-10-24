import SwiftUI

struct CrestButterPlaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(
            to: CGPoint(
                x: rect.minX + rect.width * 0.39,
                y: rect.minY + rect.height * 0.117
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.762,
                y: rect.minY + rect.height * 0.117
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.762,
                y: rect.minY + rect.height * 0.449
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.39,
                y: rect.minY + rect.height * 0.307
            )
        )
        path.closeSubpath()
        return path
    }
}
