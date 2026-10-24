import SwiftUI

extension View {
    func browserPinnedTabMiddleClick(
        perform: @escaping @MainActor () -> Void
    ) -> some View {
        browserOnMiddleClick(perform: perform)
    }
}
