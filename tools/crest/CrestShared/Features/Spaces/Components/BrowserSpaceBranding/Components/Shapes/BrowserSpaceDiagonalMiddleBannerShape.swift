import SwiftUI

struct BrowserSpaceDiagonalMiddleBannerShape: Shape {
    let size: CGSize

    func path(in _: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height * 0.50))
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.34))
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.50))
            path.addLine(to: CGPoint(x: 0, y: size.height * 0.68))
            path.closeSubpath()
        }
    }
}
