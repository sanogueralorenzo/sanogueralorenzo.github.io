import SwiftUI

struct BrowserSyncSettingsView: View {
    let browser: BrowserStore
    @Bindable var cloudSync: BrowserCloudSyncController

    @State private var confirmsUsingDevice = false
    @State private var confirmsUsingICloud = false
    @State private var confirmsPullingFromICloud = false
    @State private var showsDiagnostics = false

    var body: some View {
        BrowserSettingsPane(.sync) {
            Section("iCloud") {
                Toggle("Sync with iCloud", isOn: $cloudSync.isEnabled)
                    .accessibilityIdentifier("icloud-sync-enabled")

                CrestSettingsStatusRow("Status") {
                    Label(cloudSync.phase.title, systemImage: cloudSync.phase.symbol)
                        .foregroundStyle(cloudSync.phase.tint?.color ?? .secondary)
                }
                CrestSettingsStatusRow("iCloud account") {
                    Text(cloudSync.accountState.title)
                        .foregroundStyle(.secondary)
                }

                // Each button is its own row: a form row holding two buttons
                // takes one tap target on iOS, so only one of them answers.
                if cloudSync.isEnabled {
                    Button("Sync Now") {
                        Task { await cloudSync.syncNow() }
                    }
                    .disabled(!canSyncNow)
                    .accessibilityIdentifier("icloud-sync-now")

                    Button("Pull from iCloud…") {
                        confirmsPullingFromICloud = true
                    }
                    .disabled(!canSyncNow)
                    .accessibilityIdentifier("icloud-sync-pull")
                    .accessibilityHint("Downloads a fresh copy and merges it with this device’s content")
                }

                if let error = cloudSync.errorDescription {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("icloud-sync-error")
                }

                if let localError = cloudSync.localErrorDescription ?? browser.localSyncErrorDescription {
                    Label(localError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if cloudSync.skippedRecordCount > 0 {
                    Label(
                        "Some changes couldn’t be read. Update Crest on every device, then pull from iCloud.",
                        systemImage: "exclamationmark.icloud"
                    )
                    .foregroundStyle(.orange)
                }
            }

            if let conflict = cloudSync.conflict {
                Section {
                    LabeledContent(
                        "This device",
                        value: "\(conflict.localSpaceCount) Spaces, \(conflict.localRecordCount) records"
                    )
                    LabeledContent(
                        "iCloud",
                        value: "\(conflict.cloudSpaceCount) Spaces, \(conflict.cloudRecordCount) records"
                    )
                    HStack(spacing: 12) {
                        Button("Use This Device") {
                            confirmsUsingDevice = true
                        }
                        .accessibilityHint("Replaces the Crest content in iCloud with this device’s content")

                        Button("Use iCloud") {
                            confirmsUsingICloud = true
                        }
                        .accessibilityHint("Replaces this device’s Crest content with the iCloud copy")
                    }
                } header: {
                    Text("Choose which copy to keep")
                } footer: {
                    CrestFormFootnote("Sync is paused until you choose.")
                        .accessibilityIdentifier("icloud-sync-conflict")
                }
            }

            BrowserSyncContentScopeSection()

            Section {
                LabeledContent("Diagnostics") {
                    Button("Show…") { showsDiagnostics = true }
                        .accessibilityIdentifier("icloud-sync-diagnostics")
                }
            }
        }
        .sheet(isPresented: $showsDiagnostics) {
            BrowserSyncDiagnosticsSheet(cloudSync: cloudSync)
        }
        .confirmationDialog(
            "Pull the Latest from iCloud?",
            isPresented: $confirmsPullingFromICloud,
            titleVisibility: .visible
        ) {
            Button("Pull and Merge") {
                Task { await cloudSync.pullFromICloud() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Crest will download all synced Spaces and browser content and merge them with this device. Newer changes and synced deletions will be applied. Content found only on this device will be kept unless it was explicitly deleted on another device."
            )
        }
        .confirmationDialog(
            "Replace the iCloud Copy?",
            isPresented: $confirmsUsingDevice
        ) {
            Button("Replace iCloud with This Device", role: .destructive) {
                Task { await cloudSync.resolveUsingThisDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Crest will upload this device’s Spaces and browser content over the current iCloud copy. Other devices will receive this version on their next sync."
            )
        }
        .confirmationDialog(
            "Replace This Device’s Copy?",
            isPresented: $confirmsUsingICloud
        ) {
            Button("Replace This Device with iCloud", role: .destructive) {
                Task { await cloudSync.resolveUsingICloud() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Crest will replace the synced Spaces and browser content on this device with the current iCloud copy.")
        }
    }

    private var canSyncNow: Bool {
        cloudSync.accountState == .available
            && cloudSync.conflict == nil
            && cloudSync.phase != .syncing
    }
}
