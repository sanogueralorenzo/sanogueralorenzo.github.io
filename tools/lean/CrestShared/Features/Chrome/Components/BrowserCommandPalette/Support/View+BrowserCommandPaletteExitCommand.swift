import SwiftUI

extension View {
    /// Closes the palette on the Mac's exit command; touch has none.
    func browserPaletteExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
            onExitCommand(perform: action)
        #else
            self
        #endif
    }
}
