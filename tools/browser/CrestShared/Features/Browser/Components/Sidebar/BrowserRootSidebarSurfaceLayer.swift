import SwiftUI

struct BrowserRootSidebarSurfaceLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let edge: HorizontalEdge
    let space: SpaceModel?
    let reduceTransparency: Bool
    let spaces: [SpaceModel]
    /// Whether the pointer brought a floating sidebar out by reaching the
    /// window edge.
    let isRevealedByPointer: Bool
    let hoverChanged: @MainActor @Sendable (Bool) -> Void
    let content: Content

    @Environment(\.layoutDirection) private var layoutDirection

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        edge: HorizontalEdge = .leading,
        space: SpaceModel?,
        reduceTransparency: Bool,
        spaces: [SpaceModel] = [],
        isRevealedByPointer: Bool = false,
        hoverChanged: @escaping @MainActor @Sendable (Bool) -> Void,
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
                    // A hidden sidebar tracks nothing, and its tracker would
                    // stay over the page it slid away from, where it would
                    // take the page's cursor updates.
                    if presentation.showsSidebar {
                        BrowserSidebarHoverTracker(
                            isRevealedByPointer: isRevealedByPointer,
                            onHoverChange: hoverChanged
                        )
                        .accessibilityHidden(true)
                    }
                }
            #else
                .onHover(perform: hoverChanged)
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
        usesFloatingCardAppearance
            ? BrowserSidebarPresentation.floatingCardCornerRadius
            : 0
    }

    private var surfaceRegionWidth: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentation.floatingHoverRegionWidth(
                sidebarWidth: width
            )
            : width
    }

    private var hiddenOffset: CGFloat {
        guard presentation == .collapsed else { return 0 }
        return layoutDirection.leadingOffset(edge == .leading ? -surfaceRegionWidth : surfaceRegionWidth)
    }
}
