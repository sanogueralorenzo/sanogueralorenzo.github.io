import SwiftUI

struct CrestStartPageMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let palette = CrestStartPageMarkPalette(colorScheme: colorScheme)

            ZStack {
                RoundedRectangle(
                    cornerRadius: side * CrestStartPageMarkMetrics.cornerRadiusRatio,
                    style: .continuous
                )
                .fill(palette.background)

                ZStack {
                    CrestBannerShape()
                        .fill(palette.coral)

                    CrestButterPlaneShape()
                        .fill(palette.butter)

                    CrestSkyPlaneShape()
                        .fill(palette.sky)

                    Rectangle()
                        .fill(palette.rail)
                        .frame(width: side * CrestStartPageMarkMetrics.railWidthRatio)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipShape(CrestBannerShape())
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .overlay {
                RoundedRectangle(
                    cornerRadius: side * CrestStartPageMarkMetrics.cornerRadiusRatio,
                    style: .continuous
                )
                .strokeBorder(
                    .primary.opacity(CrestStartPageMarkMetrics.borderOpacity),
                    lineWidth: CrestStartPageMarkMetrics.borderWidth
                )
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        CrestStartPageMark().frame(width: 80, height: 80).padding()
    }
#endif
