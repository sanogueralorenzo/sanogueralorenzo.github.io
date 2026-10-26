import SwiftUI

struct BrowserSystemPermissionRow: View {
    let permission: BrowserSystemPermission
    let status: BrowserSystemPermissionStatus
    let error: String?
    let isWorking: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Label(status.state.title, systemImage: status.state.symbol)
                    .foregroundStyle(status.state.tint)
                    .accessibilityLabel(
                        "\(String(localized: permission.title)): \(String(localized: status.state.title))")
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    primaryAction
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("system-permission-\(permission.name)")
    }

    private var primaryAction: some View {
        status.state.primaryAction(self)
    }
}
