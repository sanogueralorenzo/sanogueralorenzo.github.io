import SwiftUI

/// iOS draws no separate custom keyboard focus ring for these touch controls.
struct CrestPlatformFocusShapeModifier<FocusShape: Shape>: ViewModifier {
    let shape: FocusShape

    func body(content: Content) -> some View {
        content
    }
}
