import SwiftUI

/// Touch editing already follows the shared focus and submit actions.
struct PlatformInlineSpaceNameDismissal: View {
    let isEditing: Bool
    let finish: () -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
