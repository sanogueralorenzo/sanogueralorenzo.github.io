import SwiftUI

struct BrowserNavigationFailureSuggestionRow: View {
    let suggestion: LocalizedStringResource
    let accent: Color

    var body: some View {
        Label {
            Text(suggestion)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(accent)
                .accessibilityHidden(true)
        }
        .font(.callout)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureSuggestionRow(
            suggestion: "Check your internet connection and try again.", accent: .indigo
        ).padding().frame(width: 360)
    }
#endif
