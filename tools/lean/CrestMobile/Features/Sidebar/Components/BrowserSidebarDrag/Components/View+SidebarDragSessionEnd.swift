import SwiftUI

extension View {
    /// Ends the drag `state` began as `token` once the system says the drag
    /// ended or delivered its data, where iOS reports its drag sessions.
    @ViewBuilder
    func endingSidebarDrag<Item: Equatable>(
        _ token: @escaping @MainActor () -> BrowserDragSessionToken?, in state: BrowserSidebarDragState<Item>
    ) -> some View {
        #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                onDragSessionUpdated { session in
                    switch session.phase {
                    case .ended, .dataTransferCompleted:
                        Task { @MainActor in
                            guard let token = token() else { return }
                            state.end(session: token)
                        }
                    default:
                        return
                    }
                }
            } else {
                self
            }
        #else
            self
        #endif
    }
}
