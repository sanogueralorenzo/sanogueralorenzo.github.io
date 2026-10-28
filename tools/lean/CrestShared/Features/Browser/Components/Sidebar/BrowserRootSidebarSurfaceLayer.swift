import SwiftUI

struct BrowserRootSidebarSurfaceLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let edge: HorizontalEdge
    let space: SpaceModel?
    let reduceTransparency: Bool
    let spaces: [SpaceModel]
    let isRevealedByPointer: Bool
    let hoverChanged: @MainActor @Sendable (Bool) -> Void
    let content: Content

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.browserWindowCornerRadius) private var windowCornerRadius
    private var appearance: BrowserChromeAppearance { .init(windowCornerRadius: windowCornerRadius) }

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        edge: HorizontalEdge = .leading,
        space: SpaceModel?,
        reduceTransparency: Bool,
        spaces: [SpaceModel] = [],
        isRevealedByPointer: Bool = false,
        hoverChanged: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.edge = edge
        self.space = space
        self.reduceTransparency = reduceTransparency
        self.spaces = spaces
        self.isRevealedByPointer = isRevealedByPointer
        self.hoverChanged = hoverChanged
        self.content = content()
    }

    var body: some View {
        cardSurface
            .padding(surfaceInset)
            .frame(width: surfaceRegionWidth)
            .frame(maxHeight: .infinity)
            #if os(macOS)
                .background {
                    // The gap around a floating card stands over the window's
                    // frame, and moves the window as the frame does.
                    if usesFloatingCardAppearance, presentation.showsSidebar {
                        BrowserWindowTitleBarSurface().accessibilityHidden(true)
                    }
                }
            #endif
            .contentShape(.interaction, .rect)
            #if os(macOS)
                .overlay {
                    if presentation.showsSidebar {
                        // A floating card keeps its hover over a margin of the
                        // page beside it. The tracker never takes hits, so the
                        // page still gets every click and scroll there.
                        BrowserSidebarHoverTracker(
                            isRevealedByPointer: isRevealedByPointer,
                            onHoverChange: hoverChanged
                        )
                        // Include the card's inset in the total hover margin.
                        .padding(surfaceInset - BrowserSidebarPresentation.floatingHoverMargin)
                        .accessibilityHidden(true)
                    }
                }
            #endif
            .offset(x: hiddenOffset)
            .allowsHitTesting(presentation.showsSidebar)
            .accessibilityHidden(!presentation.showsSidebar)
            .zIndex(
                presentation == .floating
                    ? BrowserRootMetrics.floatingSidebarZIndex
                    : 0
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
    }

    private var cardSurface: some View {
        content
            .animation(nil, value: presentation)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background {
                if usesFloatingCardAppearance {
                    SpaceBackdropBlend(spaces: spaces, selectedSpace: space) {
                        BrowserFloatingSidebarCardBackground(space: $0)
                    }
                }
            }
            .compositingGroup()
            // A docked sidebar's list runs on under the bottom safe area, into
            // the display's corner, as the page beside it does; a floating
            // card keeps to its rounded shape.
            .mask {
                shape.ignoresSafeArea(.container, edges: usesFloatingCardAppearance ? [] : .bottom)
            }
            .overlay {
                shape
                    .strokeBorder(
                        .primary.opacity(
                            usesFloatingCardAppearance
                                ? BrowserRootMetrics.floatingSidebarBorderOpacity
                                : 0
                        ),
                        lineWidth: BrowserRootMetrics.floatingSidebarBorderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    reduceTransparency || !usesFloatingCardAppearance || !presentation.showsSidebar
                        ? 0
                        : BrowserRootMetrics.floatingSidebarShadowOpacity
                ),
                radius: BrowserRootMetrics.floatingSidebarShadowRadius,
                x: BrowserRootMetrics.floatingSidebarShadowOffset,
                y: BrowserRootMetrics.floatingSidebarShadowOffset
            )
            .contentShape(.interaction, shape)
    }

    private var usesFloatingCardAppearance: Bool {
        presentation != .docked
    }

    private var surfaceInset: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentation.floatingCardInset
            : 0
    }

    private var surfaceCornerRadius: CGFloat {
        guard usesFloatingCardAppearance else { return 0 }
        let windowCornerRadius = appearance.windowCornerRadius ?? BrowserChromeLayout.pageCornerRadius
        return max(0, windowCornerRadius - surfaceInset)
    }

    private var surfaceRegionWidth: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentation.floatingRegionWidth(
                sidebarWidth: width
            )
            : width
    }

    /// The side of the sidebar the page lies on.
    private var pageEdge: HorizontalEdge {
        edge == .leading ? .trailing : .leading
    }

    private var hiddenOffset: CGFloat {
        guard presentation == .collapsed else { return 0 }
        return layoutDirection.leadingOffset(edge == .leading ? -surfaceRegionWidth : surfaceRegionWidth)
    }
}
