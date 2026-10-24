import SwiftUI

struct BrowserSystemPermissionRow: View {
    let permission: BrowserSystemPermission
    let status: BrowserSystemPermissionStatus
    let error: String?
    let isWorking: Bool
    let spaceName: String?
    let request: () -> Void
    let openSettings: () -> Void
    let chooseFolder: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Label(status.state.title, systemImage: status.state.symbol)
                    .foregroundStyle(status.state.tint)
                    .accessibilityLabel(
                        "\(String(localized: permission.title)): \(String(localized: status.state.title))")
                if isWorking {
                    ProgressView().controlSize(.small)
                } else if permission.checksSpaceFolder, spaceName != nil {
                    Menu("Manage") {
                        Button("Check Access", action: request)
                        Button("Choose Folder…", action: chooseFolder)
                        Button("System Settings…", action: openSettings)
                    }
                    .fixedSize()
                } else {
                    primaryAction
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("system-permission-\(permission.name)")
    }

    /// Only the download-folder check needs words: it is about one Space.
    private var caption: String? {
        guard permission.checksSpaceFolder else { return nil }
        guard let spaceName else { return String(localized: "Unlock a Space to check its download folder") }
        return String(localized: "Download folder for \(spaceName)")
    }

    private var primaryAction: some View {
        status.state.primaryAction(self)
    }
}
