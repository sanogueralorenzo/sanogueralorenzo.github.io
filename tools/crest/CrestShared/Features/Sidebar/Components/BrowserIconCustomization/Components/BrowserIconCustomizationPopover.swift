import SwiftUI

extension View {
    func browserIconCustomizationPopover(
        _ presentation: BrowserIconCustomizationPresentation,
        arrowEdge: Edge? = .trailing
    ) -> some View {
        modifier(
            BrowserIconCustomizationPopoverModifier(
                presentation: presentation,
                arrowEdge: arrowEdge
            )
        )
    }
}

private struct BrowserIconCustomizationPopoverModifier: ViewModifier {
    let presentation: BrowserIconCustomizationPresentation
    let arrowEdge: Edge?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if let preferredArrowEdge {
            content.popover(
                isPresented: presentation.isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: preferredArrowEdge
            ) {
                popoverContent
            }
        } else {
            content.popover(
                isPresented: presentation.isPresented,
                attachmentAnchor: .rect(.bounds)
            ) {
                popoverContent
            }
        }
    }

    /// Compact windows let the system choose an edge that fits the picker.
    private var preferredArrowEdge: Edge? {
        horizontalSizeClass == .compact ? nil : arrowEdge
    }

    private var popoverContent: some View {
        BrowserIconCustomizationView(
            title: presentation.title,
            currentEmoji: presentation.currentEmoji,
            currentSystemSymbol: presentation.currentSystemSymbol,
            showsReset: presentation.showsReset,
            resetTitle: presentation.resetTitle,
            setEmoji: presentation.setEmoji,
            setSystemSymbol: presentation.setSystemSymbol,
            reset: presentation.reset
        )
        .presentationCompactAdaptation(.popover)
    }
}
