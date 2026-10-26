import SwiftUI

struct BrowserExtensionPinButton: View {
    // MARK: - Static Variables

    private static let size: CGFloat = 14

    // MARK: - Variables

    let isPinned: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                .font(.system(size: 8, weight: .semibold))
        }
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: CGSize(width: Self.size, height: Self.size),
                cornerRadius: Self.size / 2,
                showsRestingFill: true
            )
        )
        .accessibilityLabel(isPinned ? "Unpin Extension" : "Pin Extension")
        .help(isPinned ? "Unpin Extension" : "Pin Extension")
    }
}

#if DEBUG
    #Preview("Pin and unpin") {
        @Previewable @State var pinned = false
        BrowserExtensionPinButton(isPinned: pinned, action: { pinned.toggle() }).padding()
    }
#endif
