import SwiftUI

struct CrestSettingsStatusRow<Status: View>: View {
    let title: LocalizedStringResource
    private let status: Status

    init(
        _ title: LocalizedStringResource,
        @ViewBuilder status: () -> Status
    ) {
        self.title = title
        self.status = status()
    }

    var body: some View {
        HStack(
            alignment: .center,
            spacing: CrestSettingsPresentationMetrics.statusSpacing
        ) {
            Text(title)
            Spacer(minLength: 0)
            status
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        Form {
            CrestSettingsStatusRow("Sync") {
                Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }.crestSettingsForm().frame(width: 400, height: 150)
    }
#endif
