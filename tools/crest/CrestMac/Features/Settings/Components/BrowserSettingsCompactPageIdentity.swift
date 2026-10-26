import SwiftUI

/// A page's name in one bar-height row, the way a settings window names the
/// pane it shows, with the way back for a sub-page.
struct BrowserSettingsCompactPageIdentity: View {
    let destination: BrowserSettingsDestination
    var back: BrowserSettingsPageBack? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let back {
                Button(action: back.action) {
                    Label {
                        Text(back.title)
                    } icon: {
                        Image(systemName: "chevron.left")
                    }
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help(Text(back.title))
                .accessibilityLabel(Text("Back to \(String(localized: back.title))"))
                .accessibilityIdentifier("settings-page-back")
            }
            Text(destination.title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, CrestSpacing.large)
        .background(BrowserSettingsCanvas.background)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-page-header")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSettingsCompactPageIdentity(destination: .privacy).padding()
    }
#endif
