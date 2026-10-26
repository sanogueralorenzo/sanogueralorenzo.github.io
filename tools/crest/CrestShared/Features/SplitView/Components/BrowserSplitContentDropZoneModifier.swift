import SwiftUI

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
