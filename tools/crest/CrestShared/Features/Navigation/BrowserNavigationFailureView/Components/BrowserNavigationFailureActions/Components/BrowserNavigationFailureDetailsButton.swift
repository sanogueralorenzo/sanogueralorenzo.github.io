import SwiftUI

struct BrowserNavigationFailureDetailsButton: View {
    let showsDetails: Bool
    let action: () -> Void

    private var title: LocalizedStringResource {
        showsDetails ? "Hide Details" : "Details"
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: showsDetails ? "chevron.up" : "info.circle")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("navigation-failure-details")
    }
}

#if DEBUG
    #Preview("Toggle details") {
        @Previewable @State var details = false
        BrowserNavigationFailureDetailsButton(showsDetails: details, action: { details.toggle() }).padding()
    }
#endif
