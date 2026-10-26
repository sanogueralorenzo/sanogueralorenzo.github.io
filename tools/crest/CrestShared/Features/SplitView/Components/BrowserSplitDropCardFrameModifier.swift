import SwiftUI

struct BrowserSplitDropCardFrameModifier: ViewModifier {
    let tabID: UUID?
    let assignment: BrowserSpaceRuntimeAssignment?
    let state: BrowserSidebarReorderState

    @State private var identity = UUID()
    @State private var frame = CGRect.zero
    /// What this view last registered, so a changed tab — a new selection under
    /// an unchanged surface — takes its predecessor's entry with it.
    @State private var registeredTabID: UUID?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { newFrame in
                frame = newFrame
                register()
            }
            .onChange(of: tabID) { _, _ in
                register()
            }
            .onChange(of: assignment) { _, _ in
                register()
            }
            .onDisappear {
                unregister()
            }
    }

    private func register() {
        if let registeredTabID, registeredTabID != tabID {
            state.removeSplitCardFrame(for: registeredTabID, owner: identity)
            self.registeredTabID = nil
        }
        guard let tabID, let assignment, !frame.isEmpty else { return }
        state.register(
            splitCardFrame: frame,
            for: tabID,
            in: assignment,
            owner: identity
        )
        registeredTabID = tabID
    }

    private func unregister() {
        guard let registeredTabID else { return }
        state.removeSplitCardFrame(for: registeredTabID, owner: identity)
        self.registeredTabID = nil
    }
}
