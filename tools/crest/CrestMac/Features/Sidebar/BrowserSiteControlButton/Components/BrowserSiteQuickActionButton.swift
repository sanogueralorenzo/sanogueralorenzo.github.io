import SwiftUI

struct BrowserSiteQuickActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: BrowserSiteControlMetrics.quickActionGlyphSize,
                        weight: .medium
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: BrowserSiteControlMetrics.quickActionHeight)
        }
        .buttonStyle(
            CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact, showsRestingFill: true)
        )
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSiteQuickActionButton(title: "Site Settings", systemImage: "gearshape", action: {}).padding()
    }
#endif
