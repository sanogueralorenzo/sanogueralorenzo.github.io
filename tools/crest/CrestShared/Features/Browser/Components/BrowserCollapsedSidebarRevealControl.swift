import SwiftUI

/// The invisible strip along the leading edge that brings a collapsed sidebar
/// back.
///
/// It is a button in every shell, because the reveal has to be reachable by
/// something other than the gesture that usually performs it — a pointer that
/// never rests on the edge, Full Keyboard Access, VoiceOver. What each shell's
/// inputs add on top of the button is capability-driven: a resting pointer
/// where there is one, an inward swipe where there are fingers.
///
/// A resting pointer reveals the sidebar only in the focused window. A pointer
/// crossing the edge of a window behind another is on its way somewhere else,
/// and the sidebar it brought out would stay until that window was focused
/// again, because nothing in a background window reports the pointer leaving.
struct BrowserCollapsedSidebarRevealControl: View {
    let capabilities: BrowserInteractionCapabilities
    let showSidebar: () -> Void
    /// Whether the strip reveals the sidebar for a resting pointer itself. A
    /// shell that tracks the pointer at the edge on its own turns this off.
    var revealsOnHover = true
    var edge: HorizontalEdge = .leading
    var isWindowFocused = true
    /// Replaces the strip's width where a pointer shell lets people choose it.
    /// Touch shells ignore it: a finger needs the width the profile gives it.
    var pointerWidth: CGFloat?

    @Environment(\.layoutDirection) private var layoutDirection

    private var metrics: BrowserCollapsedSidebarRevealMetrics {
        .resolve(capabilities)
    }

    var body: some View {
        Button(action: showSidebar) {
            revealArea
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Sidebar Temporarily")
        .accessibilityIdentifier("show-sidebar")
        .help(hint)
        .onHover { isHovering in
            guard revealsOnHover, metrics.revealsOnHover, isWindowFocused, isHovering else { return }
            showSidebar()
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        // Simultaneous rather than exclusive: the button already claims the
        // press, and a swipe that has to wait for it to fail would have to
        // travel the width of the strip before it started.
        .simultaneousGesture(
            DragGesture(minimumDistance: metrics.swipeDistance ?? 0)
                .onEnded(revealIfSwipedInward),
            isEnabled: metrics.swipeDistance != nil
        )
    }

    private var width: CGFloat {
        metrics.revealsOnHover ? pointerWidth ?? metrics.width : metrics.width
    }

    /// Where the strip answers: all of it, or on touch only its top and bottom,
    /// since the middle of the edge is where a swipe in steps the page's
    /// history. A clear colour takes no touches without a content shape, so the
    /// middle falls through to the page.
    private var revealArea: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.clear.contentShape(.rect)
                Color.clear.frame(height: proxy.size.height * metrics.pageNavigationShare)
                Color.clear.contentShape(.rect)
            }
        }
    }

    /// What the strip tells someone who stops on it: whichever input this shell
    /// actually answers.
    private var hint: LocalizedStringKey {
        metrics.swipeDistance == nil
            ? (edge == .leading
                ? "Move the pointer to the leading edge to preview the sidebar"
                : "Move the pointer to the trailing edge to preview the sidebar")
            : (edge == .leading
                ? "You can also swipe inward from the leading edge"
                : "You can also swipe inward from the trailing edge")
    }

    private func revealIfSwipedInward(_ value: DragGesture.Value) {
        guard
            layoutDirection.isLeadingEdgeReveal(
                CGSize(width: value.translation.width * (edge == .leading ? 1 : -1), height: value.translation.height))
        else { return }
        showSidebar()
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCollapsedSidebarRevealControl(capabilities: BrowserInteractionCapabilities(), showSidebar: {}).padding()
            .frame(width: 160, height: 120)
    }
#endif
