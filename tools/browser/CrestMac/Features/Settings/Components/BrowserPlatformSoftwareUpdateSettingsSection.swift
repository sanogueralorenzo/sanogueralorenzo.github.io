import SwiftUI

struct BrowserPlatformSoftwareUpdateSettingsSection: View {
    // MARK: - Variables

    @Environment(BrowserSoftwareUpdateService.self) private var softwareUpdates

    var body: some View {
        Section {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { softwareUpdates.automaticallyChecksForUpdates },
                    set: softwareUpdates.setAutomaticallyChecksForUpdates
                )
            )

            Toggle(
                "Download and install updates automatically",
                isOn: Binding(
                    get: { softwareUpdates.automaticallyDownloadsUpdates },
                    set: softwareUpdates.setAutomaticallyDownloadsUpdates
                )
            )
            .disabled(!softwareUpdates.automaticallyChecksForUpdates)

            Picker(
                "Update channel",
                selection: Binding(
                    get: { softwareUpdates.channel },
                    set: { softwareUpdates.channel = $0 }
                )
            ) {
                ForEach(BrowserSoftwareUpdateChannel.offered) { channel in
                    Text(channel.title).tag(channel)
                }
            }

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
        } footer: {
            Text(softwareUpdates.channel.guidance).crestFormFootnote()
        }
    }
}
