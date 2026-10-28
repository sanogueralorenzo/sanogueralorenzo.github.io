import SwiftUI

/// macOS exposes a dedicated focus-effect content shape for keyboard rings.
struct CrestPlatformFocusShapeModifier<FocusShape: Shape>: ViewModifier {
    let shape: FocusShape

    func body(content: Content) -> some View {
        content.contentShape(.focusEffect, shape)
    }
}
