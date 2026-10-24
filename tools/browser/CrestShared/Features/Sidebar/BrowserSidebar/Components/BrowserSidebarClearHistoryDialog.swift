import SwiftUI

/// The confirmation the sidebar puts up before it clears a Space's history.
///
/// Both shells asked the same question with the same words and dropped the
/// request the moment the Space stopped being the selected, unlocked one it was
/// asked about — a Space can be reselected, relocked, or deleted while the
/// dialog is up, and clearing the wrong Space's history is not recoverable.
struct BrowserSidebarClearHistoryDialog: ViewModifier {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @Binding var confirmation: BrowserSidebarClearHistoryConfirmation?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                title,
                isPresented: isPresented,
                titleVisibility: .visible,
                presenting: confirmation
            ) { request in
                Button("Clear History", role: .destructive) {
                    confirmation = nil
                    request.clearHistory(in: browser, accessController: spaceAccess)
                }
            } message: { _ in
                Text("History in other Spaces is not affected.")
            }
            .onChange(of: isLive) { _, isLive in
                guard !isLive else { return }
                confirmation = nil
            }
    }

    private var title: String {
        confirmation.map { "Clear history for \($0.spaceName)?" }
            ?? "Clear history?"
    }

    private var isPresented: Binding<Bool> {
        Binding {
            isLive
        } set: { isPresented in
            if !isPresented {
                confirmation = nil
            }
        }
    }

    private var isLive: Bool {
        guard let confirmation else { return false }
        return confirmation.isLive(in: browser, accessController: spaceAccess)
    }
}
