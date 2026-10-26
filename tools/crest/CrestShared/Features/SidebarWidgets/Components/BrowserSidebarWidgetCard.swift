import SwiftUI

struct BrowserSidebarWidgetCard: View {
    let instance: BrowserSidebarWidgetInstance
    /// Zero identifies the active card; rear-card content fades with depth.
    let depth: Int
    /// Rear cards use the active card's height.
    let fixedHeight: CGFloat?
    let perform: (BrowserSidebarWidgetAction, BrowserSidebarWidgetID) -> Void
    let activateMediaSession: (BrowserTabRuntimeAssignment) -> Void
    let ownerFaviconData: (BrowserTabRuntimeAssignment) -> Data?

    var body: some View {
        presentation
            .padding(CrestSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: fixedHeight, alignment: .top)
            .opacity(BrowserSidebarWidgetDeckStyle.contentOpacity(forDepth: depth))
            .modifier(BrowserSidebarWidgetCardContentFade(depth: depth))
            .clipShape(BrowserSidebarWidgetDeckStyle.cardShape)
            .modifier(BrowserSidebarWidgetCardChrome(depth: depth))
            .contentShape(BrowserSidebarWidgetDeckStyle.cardShape)
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var presentation: some View {
        switch instance.presentation {
        case .nowPlaying(let session):
            BrowserNowPlayingSidebarWidget(
                instance: instance,
                session: session,
                faviconData: ownerFaviconData(session.owner),
                perform: perform,
                activate: activateMediaSession
            )
        case .softwareUpdate(let update):
            BrowserSoftwareUpdateSidebarWidget(
                instance: instance,
                update: update,
                perform: perform
            )
        }
    }

}

/// Fades rear-card controls before the clipping edge.
private struct BrowserSidebarWidgetCardContentFade: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        if BrowserSidebarWidgetDeckStyle.masksContent(forDepth: depth) {
            content.mask { BrowserSidebarWidgetDeckStyle.contentMask }
        } else {
            content
        }
    }
}

/// Applies the selected glass or custom material treatment.
private struct BrowserSidebarWidgetCardChrome: ViewModifier {
    let depth: Int

    func body(content: Content) -> some View {
        if BrowserSidebarWidgetDeckStyle.usesLiquidGlass {
            content.glassEffect(
                .regular,
                in: BrowserSidebarWidgetDeckStyle.cardShape
            )
        } else {
            crestChrome(content)
        }
    }

    private func crestChrome(_ content: Content) -> some View {
        content
            .background { CrestSurfaceLayer(shape: BrowserSidebarWidgetDeckStyle.cardShape) }
            .overlay {
                BrowserSidebarWidgetDeckStyle.cardShape
                    .stroke(
                        BrowserSidebarWidgetDeckStyle.edgeHighlight(scale: chromeScale),
                        lineWidth: BrowserSidebarWidgetDeckStyle.cardStrokeWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    BrowserSidebarWidgetDeckStyle.contactShadowOpacity * chromeScale
                ),
                radius: BrowserSidebarWidgetDeckStyle.contactShadowRadius,
                y: BrowserSidebarWidgetDeckStyle.contactShadowOffset
            )
            .shadow(
                color: .black.opacity(CrestOpacity.controlShadow * chromeScale),
                radius: BrowserSidebarWidgetDeckStyle.ambientShadowRadius,
                y: BrowserSidebarWidgetDeckStyle.ambientShadowOffset
            )
    }

    private var chromeScale: Double {
        depth == 0 ? 1 : BrowserSidebarWidgetDeckStyle.underCardShadowScale
    }
}
