import SwiftUI

extension View {
    func crestSettingsForm(
        maxWidth: CGFloat = BrowserSettingsLayout.maximumReadableContentWidth
    ) -> some View {
        modifier(CrestPlatformSettingsFormModifier(maxWidth: maxWidth))
    }
}
