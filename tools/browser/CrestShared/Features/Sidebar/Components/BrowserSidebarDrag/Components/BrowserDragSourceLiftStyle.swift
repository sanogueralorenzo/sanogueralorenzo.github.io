import SwiftUI

/// How a tab or folder row being dragged out of the sidebar looks while it is
/// away: risen, faded and shadowed.
struct BrowserDragSourceLiftStyle: ViewModifier {
    /// Whether the row's own drag is in flight.
    let isDragging: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isDragging = usesPersistentSourceStyle
        content
            .scaleEffect(isDragging ? 1.04 : 1)
            .opacity(isDragging ? 0.42 : 1)
            .shadow(
                color: .black.opacity(isDragging ? 0.24 : 0),
                radius: isDragging ? 10 : 0,
                y: isDragging ? 5 : 0
            )
            .zIndex(isDragging ? 2 : 0)
            .animation(
                CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
                value: isDragging
            )
    }

    /// SwiftUI owns the native lift preview on mobile. Keep Crest's persistent
    /// source-row treatment only where the source also receives a guaranteed
    /// terminal callback; otherwise a context-menu long press can leave the
    /// row dimmed after the gesture has already ended.
    private var usesPersistentSourceStyle: Bool {
        isDragging && BrowserTabDragState.hasReliableTerminalLifecycle
    }
}
