import SwiftUI

struct MobileCompactStartPageToolbar: View {
    let showTabViewer: () -> Void

    var body: some View {
        HStack {
            Spacer()

            GlassEffectContainer(spacing: 0) {
                MobileCompactIconButton(
                    title: "Tabs",
                    systemImage: "square.on.square",
                    action: showTabViewer
                )
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityIdentifier("tab-viewer-button")
            }
        }
        .padding(
            .horizontal,
            MobileBrowserChromeLayout.compactToolbarHorizontalPadding
        )
        .padding(
            .vertical,
            MobileBrowserChromeLayout.compactToolbarVerticalPadding
        )
    }
}

#if DEBUG
    #Preview("Component") {
        MobileCompactStartPageToolbar(showTabViewer: {}).frame(width: 390).padding()
    }
#endif
