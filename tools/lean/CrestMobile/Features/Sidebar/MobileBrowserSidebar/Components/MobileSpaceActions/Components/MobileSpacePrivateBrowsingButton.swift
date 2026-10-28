import SwiftUI

struct MobileSpacePrivateBrowsingButton: View {
    let isPrivateBrowsing: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MobileSpaceUtilityButtonLabel(
                systemImage: BrowserPrivateBrowsingAppearance.symbol
            )
        }
        .foregroundStyle(isPrivateBrowsing ? accentColor : Color.primary)
        .accessibilityLabel(
            isPrivateBrowsing ? "Leave Private Browsing" : "Private Browsing"
        )
        .accessibilityValue(isPrivateBrowsing ? "On" : "Off")
        .accessibilityIdentifier("private-browsing-toggle")
    }
}

#if DEBUG
    #Preview("Toggle private appearance") {
        @Previewable @State var isPrivate = false
        MobileSpacePrivateBrowsingButton(
            isPrivateBrowsing: isPrivate, accentColor: .indigo, action: { isPrivate.toggle() }
        ).padding()
    }
#endif
