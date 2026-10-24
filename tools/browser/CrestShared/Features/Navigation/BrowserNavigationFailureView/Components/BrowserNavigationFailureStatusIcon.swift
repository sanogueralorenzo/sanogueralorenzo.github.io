import SwiftUI

struct BrowserNavigationFailureStatusIcon: View {
    let symbolName: String
    let accent: Color
    let iconSize: CGFloat

    var body: some View {
        Image(systemName: symbolName)
            .font(
                .system(
                    size: iconSize * BrowserNavigationFailureMetrics.iconSymbolScale,
                    weight: .semibold
                )
            )
            .foregroundStyle(accent)
            .frame(width: iconSize, height: iconSize)
            .background(
                accent.opacity(BrowserNavigationFailureMetrics.iconBackgroundOpacity),
                in: .rect(
                    cornerRadius: iconSize
                        * BrowserNavigationFailureMetrics.iconCornerScale
                )
            )
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Offline and certificate") {
        HStack(spacing: 24) {
            BrowserNavigationFailureStatusIcon(symbolName: "wifi.slash", accent: .indigo, iconSize: 48)
            BrowserNavigationFailureStatusIcon(
                symbolName: "lock.trianglebadge.exclamationmark", accent: .orange, iconSize: 48)
        }.padding()
    }
#endif
