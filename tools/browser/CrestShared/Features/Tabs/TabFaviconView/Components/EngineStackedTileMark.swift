import SwiftUI

/// The stacked tile mark: a blue tile resting on a warm one, seen from above
/// at an angle. It is Crest's own drawing in system colours, not WebKit's logo,
/// which is Apple's trademark, so it carries no compass and none of the logo's
/// proportions or colours.
///
/// It fits the frame it is given, centred, and draws no ground of its own.
struct EngineStackedTileMark: View {
    // MARK: - Static Variables

    /// The top face's height against the tile's width.
    private static let faceHeight: CGFloat = 0.56

    /// How far the warm tile shows beneath the face, against the width.
    private static let depth: CGFloat = 0.26

    /// The radius of every corner, against the width.
    private static let cornerRadius: CGFloat = 0.08

    /// The face, lighter toward its far corner.
    private static let faceColors: [Color] = [.blue.mix(with: .white, by: 0.18), .blue]

    /// The warm tile, lit from the left.
    private static let tileColors: [Color] = [.yellow, .orange]

    // MARK: - Variables

    var body: some View {
        Canvas { context, size in
            let height = Self.faceHeight + Self.depth
            let width = min(size.width, size.height / height)
            let face = Self.face(width: width)
                .offsetBy(dx: (size.width - width) / 2, dy: (size.height - width * height) / 2)
            let tile = Self.tile(under: face, depth: Self.depth * width)
            let faceBounds = face.boundingRect
            let tileBounds = tile.boundingRect
            context.fill(
                tile,
                with: .linearGradient(
                    Gradient(colors: Self.tileColors), startPoint: CGPoint(x: tileBounds.minX, y: tileBounds.midY),
                    endPoint: CGPoint(x: tileBounds.maxX, y: tileBounds.midY)))
            context.fill(
                face,
                with: .linearGradient(
                    Gradient(colors: Self.faceColors), startPoint: CGPoint(x: faceBounds.midX, y: faceBounds.minY),
                    endPoint: CGPoint(x: faceBounds.midX, y: faceBounds.maxY)))
        }
    }

    // MARK: - Actions - Geometry

    /// The top face at `width`: a diamond with rounded corners, its top
    /// corner at the origin's height.
    private static func face(width: CGFloat) -> Path {
        let corners = [
            CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: faceHeight / 2), CGPoint(x: 0.5, y: faceHeight),
            CGPoint(x: 0, y: faceHeight / 2),
        ]
        return roundedPolygon(corners.map { CGPoint(x: $0.x * width, y: $0.y * width) }, radius: cornerRadius * width)
    }

    /// The face swept straight down by `depth`: the face, the face lowered,
    /// and the band between their widest points. Drawn under the face, it
    /// shows as the warm edge beneath it.
    private static func tile(under face: Path, depth: CGFloat) -> Path {
        let bounds = face.boundingRect
        return face.union(face.offsetBy(dx: 0, dy: depth))
            .union(Path(CGRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: depth)))
    }

    private static func roundedPolygon(_ corners: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard let first = corners.first, let last = corners.last else { return path }
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for (index, corner) in corners.enumerated() {
            path.addArc(tangent1End: corner, tangent2End: corners[(index + 1) % corners.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

#if DEBUG
    #Preview("Component") {
        HStack(spacing: CrestSpacing.medium) {
            EngineStackedTileMark().frame(width: 64, height: 64)
            EngineStackedTileMark().frame(width: 16, height: 16)
            EngineStackedTileMark().frame(width: 8, height: 8)
        }
        .padding()
    }
#endif
