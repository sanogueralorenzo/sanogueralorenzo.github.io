import SwiftUI

/// VoiceOver's way through the shown Space's tabs from the address: Previous
/// Tab and Next Tab move as the address bar's swipe does, and are left out
/// where the bar walks no tabs. The address keeps its identity either way, so
/// starting to edit it never rebuilds the field it is editing in.
struct MobileTabStepActions: ViewModifier {
    let step: ((AdjacentDirection) -> Void)?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let step {
                Button("Previous Tab") { step(.previous) }
                Button("Next Tab") { step(.next) }
            }
        }
    }
}
