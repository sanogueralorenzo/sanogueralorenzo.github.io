import SwiftUI

extension View {
    func browserPaletteExitCommand(_ action: @escaping () -> Void) -> some View {
        modifier(BrowserPlatformPaletteExitCommandModifier(action: action))
    }
}
