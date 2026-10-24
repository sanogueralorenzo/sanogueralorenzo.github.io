import SwiftUI

struct BrowserSpaceBannerField: View {
    let pattern: SpaceBannerPattern
    let colors: [Color]
    let size: CGSize

    @ViewBuilder
    var body: some View {
        let second = colors[min(1, colors.count - 1)]
        let third = colors[min(2, colors.count - 1)]

        switch pattern.kind {
        case .solid:
            colors[0]
        case .split:
            HStack(spacing: 0) {
                colors[0]
                second
            }
        case .bands:
            VStack(spacing: 0) {
                colors[0]
                second
                third
            }
        case .diagonal:
            ZStack {
                colors[0]
                BrowserSpaceDiagonalMiddleBannerShape(size: size)
                    .fill(second)
                BrowserSpaceDiagonalLowerBannerShape(size: size)
                    .fill(third)
            }
        case .chevron:
            ZStack {
                colors[0]
                BrowserSpaceChevronMiddleBannerShape(size: size)
                    .fill(second)
                BrowserSpaceChevronLowerBannerShape(size: size)
                    .fill(third)
            }
        case .stripes, .checkered, .lozenges:
            Canvas { context, canvasSize in
                context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(colors[0]))
                let cell = max(16, canvasSize.width / 5)
                let rows = min(200, Int(ceil(canvasSize.height / cell)) + 1)
                let columns = min(200, Int(ceil(canvasSize.width / cell)) + 1)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let x = CGFloat(column) * cell
                        let y = CGFloat(row) * cell
                        switch pattern.kind {
                        case .stripes:
                            if column.isMultiple(of: 2) {
                                context.fill(
                                    Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                    with: .color(second.opacity(0.35)))
                            }
                        case .checkered:
                            if (row + column).isMultiple(of: 2) {
                                context.fill(
                                    Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                    with: .color(second.opacity(0.35)))
                            }
                        case .lozenges:
                            var diamond = Path()
                            diamond.move(to: CGPoint(x: x + cell / 2, y: y))
                            diamond.addLine(to: CGPoint(x: x + cell, y: y + cell / 2))
                            diamond.addLine(to: CGPoint(x: x + cell / 2, y: y + cell))
                            diamond.addLine(to: CGPoint(x: x, y: y + cell / 2))
                            diamond.closeSubpath()
                            context.fill(
                                diamond, with: .color(((row + column).isMultiple(of: 2) ? second : third).opacity(0.35))
                            )
                        default: break
                        }
                    }
                }
            }
        case .quartered:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    colors[0]
                    second
                }
                HStack(spacing: 0) {
                    third
                    colors[0]
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Banner pattern") {
        BrowserSpaceBannerField(
            pattern: .diagonal, colors: [.indigo, .cyan, .orange], size: CGSize(width: 320, height: 400)
        )
        .frame(width: 320, height: 400)
    }
#endif
