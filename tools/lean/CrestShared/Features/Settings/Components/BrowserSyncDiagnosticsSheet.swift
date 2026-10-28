import SwiftUI

/// The sync monitor's counters and the shareable report, kept off the main
/// Sync page because only troubleshooting needs them.
struct BrowserSyncDiagnosticsSheet: View {
    let cloudSync: BrowserCloudSyncController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Local records", value: cloudSync.localRecordCount.formatted())
                    LabeledContent("Pending uploads", value: cloudSync.pendingUploadCount.formatted())
                    LabeledContent(
                        "Cloud records observed",
                        value: cloudSync.observedCloudRecordCount?.formatted() ?? String(localized: "Not checked")
                    )
                    LabeledContent("Last attempt") { optionalDate(cloudSync.lastAttemptAt) }
                    LabeledContent("Last successful sync") { optionalDate(cloudSync.lastSuccessAt) }
                    LabeledContent("Last download batch", value: cloudSync.lastFetchedRecordCount.formatted())
                    LabeledContent("Last upload batch", value: cloudSync.lastUploadedRecordCount.formatted())
                    LabeledContent(
                        "CloudKit container",
                        value: cloudSync.containerIdentifier ?? String(localized: "Not configured")
                    )
                } footer: {
                    CrestFormFootnote("The report has counts only: no URLs, titles or passwords.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Sync Diagnostics")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: cloudSync.diagnosticsReport,
                        subject: Text("Crest iCloud Sync Diagnostics")
                    ) {
                        Text("Share Report")
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    @ViewBuilder
    private func optionalDate(_ date: Date?) -> some View {
        if let date {
            Text(date, style: .relative)
        } else {
            Text("Never").foregroundStyle(.secondary)
        }
    }
}
