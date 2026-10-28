import SwiftUI

extension View {
    /// Marks real rows, before the empty hit area expands to fill the viewport.
    func sidebarScrollContent() -> some View {
        modifier(SidebarScrollContentExtent())
    }
}

extension EnvironmentValues {
    @Entry fileprivate var sidebarScrollActivity: SidebarScrollActivity? = nil
}

private struct SidebarScrollContentExtent: ViewModifier {
    @Environment(\.sidebarScrollActivity) private var activity

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: { height in
            activity?.contentHeight = height
        }
    }
}

/// The same vertical-scroll affordance in windowed and touch sidebars. Its
/// geometry updates are observed only by the indicator, never the tab rows.
struct SidebarScrollAffordance: ViewModifier {
    var isDragging = false
    @State private var activity = SidebarScrollActivity()
    @State private var position = ScrollPosition()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.sidebarScrollActivity, activity)
            .scrollIndicators(.never)
            .scrollPosition($position)
            .onScrollGeometryChange(for: SidebarScrollMetrics.self) { geometry in
                SidebarScrollMetrics(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height + geometry.contentInsets.top
                        + geometry.contentInsets.bottom,
                    viewportHeight: geometry.containerSize.height,
                    visibleBottom: geometry.visibleRect.maxY)
            } action: { _, metrics in
                activity.update(metrics)
            }
            .onScrollPhaseChange { _, phase in activity.setScrolling(phase != .idle) }
            .overlay {
                SidebarScrollIndicator(activity: activity, isDragging: isDragging) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                        position.scrollTo(
                            y: min(
                                activity.metrics.maximumOffset,
                                activity.metrics.offset + activity.metrics.viewportHeight * 0.85))
                    }
                }
            }
            .onDisappear { activity.reset() }
    }
}

private struct SidebarScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var visibleBottom: CGFloat = 0
    var maximumOffset: CGFloat { max(0, contentHeight - viewportHeight) }
}

@MainActor
@Observable
private final class SidebarScrollActivity {
    var contentHeight: CGFloat = 0
    var hasMoreBelow: Bool { contentHeight > metrics.visibleBottom + 1 }
    private(set) var metrics = SidebarScrollMetrics()
    private(set) var showsIndicator = false
    @ObservationIgnored private var isScrolling = false
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    func update(_ value: SidebarScrollMetrics) {
        let moved =
            abs(value.offset - metrics.offset) > 0.5
            && value.viewportHeight == metrics.viewportHeight && value.contentHeight == metrics.contentHeight
        metrics = value
        // Discrete mouse wheels and programmatic drag autoscrolling may move
        // without a native gesture phase. They use the same idle deadline.
        if moved {
            showsIndicator = true
            if !isScrolling { scheduleIdle() }
        }
    }

    func setScrolling(_ scrolling: Bool) {
        isScrolling = scrolling
        idleTask?.cancel()
        if scrolling { showsIndicator = true } else { scheduleIdle() }
    }

    func reset() {
        idleTask?.cancel()
        idleTask = nil
        isScrolling = false
        showsIndicator = false
    }

    private func scheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            self?.showsIndicator = false
            self?.idleTask = nil
        }
    }
}

private struct SidebarScrollIndicator: View {
    let activity: SidebarScrollActivity
    let isDragging: Bool
    let scrollDown: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsBubble: Bool {
        activity.hasMoreBelow && !activity.showsIndicator && !isDragging
    }

    var body: some View {
        GeometryReader { geometry in
            let track = max(0, geometry.size.height - 8)
            let metrics = activity.metrics
            let height = min(track, max(24, track * metrics.viewportHeight / max(1, metrics.contentHeight)))
            let fraction = min(1, max(0, metrics.offset / max(1, metrics.maximumOffset)))
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.primary.opacity(0.45))
                    .frame(width: 3, height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 3)
                    .offset(y: 4 + (track - height) * fraction)
                    .opacity(activity.showsIndicator && metrics.maximumOffset > 1 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Button(action: scrollDown) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(
                            width: CrestLayout.glassIconButtonDiameter / 2,
                            height: CrestLayout.glassIconButtonDiameter / 2
                        )
                        .glassEffect(.regular.interactive(), in: .circle)
                        .frame(
                            width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget,
                            alignment: .bottom
                        )
                        .contentShape(.circle)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .scaleEffect(reduceMotion || showsBubble ? 1 : 0.5, anchor: .bottom)
                .offset(y: reduceMotion ? -6 : showsBubble ? -6 : CrestLayout.glassIconButtonDiameter + 8)
                .opacity(showsBubble ? 1 : 0)
                .allowsHitTesting(showsBubble)
                .accessibilityHidden(!showsBubble)
                .accessibilityLabel("Show more tabs")
                .accessibilityIdentifier("sidebar-more-tabs")
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activity.showsIndicator)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsBubble)
            .clipped()
        }
    }
}
