import SwiftUI

struct BrowserSoftwareUpdateSettingsSection: View {
    // MARK: - Variables

    @Environment(BrowserSoftwareUpdateService.self) private var softwareUpdates

    var body: some View {
        Section {
            if softwareUpdates.model.phase == .idle {
                HStack {
                    Spacer()
                    Button("Check for Updates…") {
                        softwareUpdates.checkForUpdates()
                    }
                    .disabled(!softwareUpdates.isEnabled)
                }
            } else {
                BrowserSoftwareUpdateStatusRow(model: softwareUpdates.model)
                BrowserSoftwareUpdateActions(model: softwareUpdates.model, confirmsWithReturn: false)
            }

            if let startErrorDescription = softwareUpdates.startErrorDescription {
                Label(
                    startErrorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        } header: {
            Text("Software updates")
        }
    }
}
