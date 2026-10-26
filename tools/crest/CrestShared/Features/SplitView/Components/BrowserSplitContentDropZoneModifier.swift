import SwiftUI

/// Offers the window's web-content area as a drop target for a dragged sidebar
/// tab, so releasing it there adds it to the cards on show.
///
/// A separate modifier from `BrowserSidebarReorderZoneModifier` for one reason:
/// every other zone's target is fixed for the life of its view — a section is
/// its placement, a folder row is its folder — while this one names the Space
/// being shown, which changes without the content area moving an inch. A zone
/// registered once from a geometry callback would keep pointing at the Space the
/// window left, and a drag in the new one would silently refuse. The measured
/// frame is therefore kept so the registration can be redone when the Space
/// changes.
///
/// A `nil` assignment registers nothing: a window with no unlocked Space has no
/// cards, and offering a drop into it would promise something the commit would
/// decline.
struct BrowserSplitContentDropZoneModifier: ViewModifier {
    let assignment: BrowserSpaceRuntimeAssignment?
    let state: BrowserSidebarReorderState

    @State private var identity = UUID()
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { newFrame in
                frame = newFrame
                register()
            }
            .onChange(of: assignment) { _, _ in
                register()
            }
            .onDisappear {
                state.removeZone(for: identity)
            }
    }

    private func register() {
        guard let assignment, !frame.isEmpty else {
            state.removeZone(for: identity)
            return
        }
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .splitContent(assignment),
                frame: frame
            ),
            for: identity
        )
    }
}
