import SwiftUI

struct MobileSettingsDestinationRow: View {
    let destination: BrowserSettingsDestination

    var body: some View {
        CrestSettingsDestinationLabel(
            title: destination.title,
            subtitle: destination.subtitle,
            systemImage: destination.symbol,
            color: destination.color
        )
        .padding(.vertical, CrestSpacing.extraExtraSmall)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
    #Preview("Settings destinations") {
        List {
            MobileSettingsDestinationRow(destination: .general)
            MobileSettingsDestinationRow(destination: .privacy)
        }.frame(width: 390, height: 240)
    }
#endif
