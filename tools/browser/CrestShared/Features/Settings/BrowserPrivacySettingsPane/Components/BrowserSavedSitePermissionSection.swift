import SwiftUI

struct BrowserSavedSitePermissionSection: View {
    let records: [SitePermissionRecordState]
    let permissionCenter: BrowserSitePermissionCenter
    let resetAll: () -> Void

    var body: some View {
        Section("Site permissions") {
            if records.isEmpty {
                Text("No saved permissions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    BrowserSitePermissionRecordRow(
                        record: record,
                        permissionCenter: permissionCenter
                    )
                }
                HStack {
                    Spacer()
                    Button("Reset All…", role: .destructive, action: resetAll)
                        .accessibilityHint("Restores each site's default permission behavior")
                }
            }
        }
    }
}
