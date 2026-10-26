import SwiftUI

struct BrowserRootShellControls: View {
    let model: BrowserRootModel
    @Binding var storedSidebarWidth: Double
    var sidebarEdge: HorizontalEdge = .leading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        switch model.sidebarPresentation.kind {
        case .collapsed:
            BrowserCollapsedSidebarRevealControl(
                capabilities: interactionCapabilities,
                showSidebar: presentFloatingSidebar,
                revealsOnHover: false,
                edge: sidebarEdge,
                isWindowFocused: model.isWindowFocused,
                pointerWidth: revealPointerWidth
            )
            // Shows the strip while its width changes in Settings.
            .background { BrowserSidebarRevealZonePreview() }
            // The Mac shell reveals for a resting pointer through AppKit alone.
            // Live WKWebView content cannot swallow the edge transition before
            // AppKit sees it, and AppKit reports only in the key window. The
            // strip's own hover reads focus a moment late, and reopened the
            // sidebar under a pointer parked at the screen edge just after the
            // window lost focus, where nothing would close it again.
            .overlay {
                if revealMetrics.revealsOnHover {
                    BrowserCollapsedSidebarHoverTracker(
                        onHoverChange: collapsedSidebarHoverChanged
                    )
                }
            }
        case .docked:
            BrowserSidebarResizeHandle(
                width: model.sidebarWidthBinding,
                onResizeEnded: commitSidebarWidth,
                edge: sidebarEdge
            )
            .offset(x: resizeHandleOffset)
            .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
        case .floating:
            EmptyView()
        }
    }

    /// How wide the collapsed sidebar's reveal strip is, as Settings sets it.
    private var revealPointerWidth: CGFloat {
        SidebarRevealWidthPreference.width(BrowserDeviceAppearanceStore.shared.sidebarRevealWidth)
    }

    /// Where the docked sidebar's resize handle sits: at the sidebar's edge,
    /// on whichever side the sidebar is.
    private var resizeHandleOffset: CGFloat {
        layoutDirection.leadingOffset(
            (model.sidebarWidth - BrowserRootMetrics.sidebarResizeHandleOffset)
                * (sidebarEdge == .leading ? 1 : -1))
    }

    private var interactionCapabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var revealMetrics: BrowserCollapsedSidebarRevealMetrics {
        .resolve(interactionCapabilities)
    }

    private func collapsedSidebarHoverChanged(_ isHovering: Bool) {
        guard isHovering, model.isWindowFocused else { return }
        model.revealFloatingSidebarFromPointer(reduceMotion: reduceMotion)
    }

    private func presentFloatingSidebar() {
        model.presentFloatingSidebar(reduceMotion: reduceMotion)
    }

    private func commitSidebarWidth(_ width: CGFloat) {
        guard let committedWidth = model.commitSidebarWidth(width) else { return }
        storedSidebarWidth = Double(committedWidth)
    }
}
