import SwiftUI

extension View {
    @MainActor
    func browserCommandPaletteHoverSelection(
        model: BrowserCommandPaletteModel,
        index: Int
    ) -> some View {
        onHover { isHovering in
            guard isHovering else { return }
            model.selectResult(at: index)
        }
    }
}
