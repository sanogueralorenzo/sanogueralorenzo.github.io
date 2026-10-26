import SwiftUI

struct BrowserSidebarClearHistoryDialog: ViewModifier {
    let browser: BrowserStore
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
                    request.clearHistory(in: browser)
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
        return confirmation.isLive(in: browser)
    }
}
