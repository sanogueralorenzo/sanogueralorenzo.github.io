import SwiftUI

struct BrowserCollapsedSidebarRevealControl: View {
    let showSidebar: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    var edge: HorizontalEdge = .leading

    var body: some View {
        Button(action: showSidebar) {
            revealArea
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show Sidebar Temporarily")
        .accessibilityIdentifier("show-sidebar")
        .help(hint)
        .frame(width: 26)
        .frame(maxHeight: .infinity)
        // Simultaneous rather than exclusive: the button already claims the
        // press, and a swipe that has to wait for it to fail would have to
        // travel the width of the strip before it started.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded(revealIfSwipedInward)
        )
    }

    /// Where the strip answers: all of it, or on touch only its top and bottom,
    /// since the middle of the edge is where a swipe in steps the page's
    /// history. A clear colour takes no touches without a content shape, so the
    /// middle falls through to the page.
    private var revealArea: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.clear.contentShape(.rect)
                Color.clear.frame(height: proxy.size.height * 0.5)
                Color.clear.contentShape(.rect)
            }
        }
    }

    /// What the strip tells someone who stops on it: whichever input this shell
    /// actually answers.
    private var hint: LocalizedStringKey {
        edge == .leading
            ? "You can also swipe inward from the leading edge"
            : "You can also swipe inward from the trailing edge"
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
        BrowserCollapsedSidebarRevealControl(showSidebar: {}).padding()
            .frame(width: 160, height: 120)
    }
#endif
