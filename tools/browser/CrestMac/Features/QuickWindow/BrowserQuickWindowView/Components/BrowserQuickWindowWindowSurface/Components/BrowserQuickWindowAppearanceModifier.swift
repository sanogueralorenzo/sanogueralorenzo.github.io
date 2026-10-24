import SwiftUI

struct BrowserQuickWindowAppearanceModifier: ViewModifier {
    let model: BrowserQuickWindowModel

    func body(content: Content) -> some View {
        content
            .background {
                BrowserQuickWindowBackdrop(space: model.spaceModel)
            }
    }
}
