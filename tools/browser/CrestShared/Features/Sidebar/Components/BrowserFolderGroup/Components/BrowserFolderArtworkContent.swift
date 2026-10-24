import SwiftUI

/// The shared folder drawing, with its optional symbol attached to the front plane.
struct BrowserFolderArtworkContent: View {
    let symbol: String
    let color: BrandColor
    var isExpanded = false
    let iconOnly: Bool
    var tintsTitle = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if iconOnly, let glyph = Self.customGlyph(for: symbol) {
            Group {
                if BrowserIconSymbol.emoji(from: symbol) != nil {
                    glyph
                } else {
                    // Use the folder's font-relative footprint. Text attachments
                    // can truncate wider symbols inside the fixed icon column.
                    Image(systemName: "folder").hidden().overlay {
                        Image(systemName: symbol).resizable().scaledToFit()
                    }
                }
            }
            .foregroundStyle(symbolStyle)
            .transaction { $0.animation = nil }
        } else {
            BrowserFolderFaces(glyph: Self.customGlyph(for: symbol), color: color, isExpanded: isExpanded)
                .foregroundStyle(faceForeground)
        }
    }

    /// Matches the tinted title beside it. Without a tint the glyph keeps the
    /// inherited hierarchical style, which a highlighted menu row inverts.
    private var symbolStyle: AnyShapeStyle {
        guard
            let tint = color.folderSymbolColor(
                for: symbol, tintsTitle: tintsTitle, onDarkBackground: colorScheme == .dark)
        else { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(tint.color)
    }

    private var faceForeground: Color {
        let scheme = color.foregroundTone.colorScheme
        return scheme == .dark ? .white : .black
    }

    static func customGlyph(for symbol: String) -> Text? {
        if let emoji = BrowserIconSymbol.emoji(from: symbol) { return Text(emoji) }
        guard symbol != "folder", symbol != "folder.fill" else { return nil }
        return Text(Image(systemName: symbol))
    }
}

/// Shared proportions and hinge angles for the folder's two flat faces.
private enum BrowserFolderGeometry {
    static let translation = 3.0
    static let yAngle = 32.0
    static let frontAngle = -30.0
    static let backAngle = 28.0
    static let perspective = -1.0 / 350.0
    static let tabHeight = 0.25
    static let tabStart = 0.42
    static let tabEnd = 0.58
    static let cornerDivisor = 7.0
}

private struct BrowserFolderFaces: View {
    let glyph: Text?
    let color: BrandColor
    let isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "folder").hidden().overlay {
            GeometryReader { proxy in
                let size = proxy.size
                let top = size.height * BrowserFolderGeometry.tabHeight
                let radius = size.width / BrowserFolderGeometry.cornerDivisor
                ZStack(alignment: .bottomLeading) {
                    Canvas { context, size in
                        let edgeInset: CGFloat = 0.5
                        context.translateBy(x: edgeInset, y: edgeInset)
                        let w = size.width - edgeInset * 2
                        let h = size.height - edgeInset * 2
                        let shoulder = top / 1.5
                        var path = Path()
                        path.move(to: CGPoint(x: radius, y: 0))
                        path.addLine(to: CGPoint(x: w * BrowserFolderGeometry.tabStart, y: 0))
                        path.addLine(to: CGPoint(x: w * BrowserFolderGeometry.tabEnd, y: shoulder))
                        path.addLine(to: CGPoint(x: w - radius, y: shoulder))
                        path.addArc(
                            center: CGPoint(x: w - radius, y: shoulder + radius), radius: radius,
                            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                        path.addLine(to: CGPoint(x: w, y: h - radius))
                        path.addArc(
                            center: CGPoint(x: w - radius, y: h - radius), radius: radius,
                            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                        path.addLine(to: CGPoint(x: radius, y: h))
                        path.addArc(
                            center: CGPoint(x: radius, y: h - radius), radius: radius,
                            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                        path.addLine(to: CGPoint(x: 0, y: radius))
                        path.addArc(
                            center: CGPoint(x: radius, y: radius), radius: radius,
                            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                        path.closeSubpath()
                        context.fill(path, with: .color(faceColor))
                        context.fill(path, with: .color(.black.opacity(0.22)))
                    }
                    .modifier(
                        BrowserFolderFaceProjection(front: false, openness: isExpanded ? 1 : 0)
                    )
                    Canvas { context, size in
                        let edgeInset: CGFloat = 0.5
                        let path = Path(
                            roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: edgeInset, dy: edgeInset),
                            cornerRadius: max(0, radius - edgeInset))
                        context.fill(path, with: .color(faceColor))
                        var tint = context
                        tint.opacity = BrandColor.folderFrontHighlightOpacity
                        tint.fill(path, with: .color(.white))
                        if let glyph {
                            context.draw(
                                glyph.font(.system(size: size.height * 0.5, weight: .semibold)),
                                at: CGPoint(x: size.width / 2, y: size.height / 2))
                        }
                    }
                    .frame(height: max(1, size.height - top))
                    .modifier(
                        BrowserFolderFaceProjection(front: true, openness: isExpanded ? 1 : 0))
                }
            }
        }
        .animation(reduceMotion ? nil : CrestMotion.collection, value: isExpanded)
    }

    private var faceColor: Color {
        color.color
    }
}

private struct BrowserFolderFaceProjection: GeometryEffect {
    let front: Bool
    var openness: Double
    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var transform = CATransform3DIdentity
        transform.m34 = BrowserFolderGeometry.perspective
        transform = CATransform3DTranslate(transform, BrowserFolderGeometry.translation * openness, 0, 0)
        transform = CATransform3DRotate(transform, BrowserFolderGeometry.yAngle * .pi / 180 * openness, 0, 1, 0)
        transform = CATransform3DRotate(
            transform,
            (front ? BrowserFolderGeometry.frontAngle : BrowserFolderGeometry.backAngle) * .pi / 180 * openness, 1, 0, 0
        )
        return ProjectionTransform(CGAffineTransform(translationX: 0, y: -size.height))
            .concatenating(ProjectionTransform(transform))
            .concatenating(ProjectionTransform(CGAffineTransform(translationX: 0, y: size.height)))
    }
}

#if DEBUG
    #Preview("Folder artwork") {
        HStack(spacing: 24) {
            BrowserFolderArtworkContent(symbol: "folder.fill", color: .ocean, isExpanded: false, iconOnly: false)
            BrowserFolderArtworkContent(symbol: "star.fill", color: .ocean, isExpanded: true, iconOnly: false)
            BrowserFolderArtworkContent(symbol: "star.fill", color: .ocean, isExpanded: false, iconOnly: true)
            BrowserFolderArtworkContent(
                symbol: "star.fill", color: .ocean, isExpanded: false, iconOnly: true, tintsTitle: true)
        }.font(.system(size: 32)).padding(32)
    }
#endif
