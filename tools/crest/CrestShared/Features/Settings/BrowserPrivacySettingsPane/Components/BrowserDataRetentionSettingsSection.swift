import SwiftUI

struct BrowserDataRetentionSettingsSection: View {
    let browser: BrowserStore
    let downloadCenter: BrowserDownloadCenter
    let spaceID: UUID

    @State private var pendingChange: BrowserDataRetentionChange?

    var body: some View {
        Section {
            ForEach(BrowserDataRetentionCategory.all) { category in
                Picker(category.title, selection: binding(for: category)) {
                    ForEach(DataRetention.all, id: \.self) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .accessibilityIdentifier(category.accessibilityIdentifier)
            }
        } header: {
            Text("Keep")
        } footer: {
            CrestFormFootnote("Removing download records doesn’t delete the files.")
        }
        .confirmationDialog(
            "Permanently delete older records?",
            isPresented: presentsConfirmation,
            titleVisibility: .visible
        ) {
            if let pendingChange {
                Button("Use \(String(localized: pendingChange.proposed.title))", role: .destructive) {
                    apply(pendingChange)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingChange = nil
            }
        } message: {
            if let pendingChange {
                Text(
                    "This immediately and permanently deletes \(pendingChange.category.cleanupDescription) older than \(String(localized: pendingChange.proposed.title).lowercased()) in this Space, including synced copies. Downloaded files stay on disk."
                )
            }
        }
    }

    private var presentsConfirmation: Binding<Bool> {
        Binding(
            get: { pendingChange != nil },
            set: { isPresented in
                if !isPresented {
                    pendingChange = nil
                }
            }
        )
    }

    private func binding(
        for category: BrowserDataRetentionCategory
    ) -> Binding<DataRetention> {
        Binding(
            get: { policy(for: category) },
            set: { proposed in
                let change = BrowserDataRetentionChange(
                    category: category,
                    previous: policy(for: category),
                    proposed: proposed
                )
                guard change.previous != change.proposed else { return }
                if change.requiresConfirmation {
                    pendingChange = change
                } else {
                    apply(change)
                }
            }
        )
    }

    private func policy(
        for category: BrowserDataRetentionCategory
    ) -> DataRetention {
        guard let retention = browser.spaceModel(spaceID)?.settings.browsingPreferences.dataRetention else {
            return .forever
        }
        return retention[keyPath: category.retention]
    }

    private func apply(_ change: BrowserDataRetentionChange) {
        guard var retention = browser.spaceModel(spaceID)?.settings.browsingPreferences.dataRetention else {
            pendingChange = nil
            return
        }
        retention[keyPath: change.category.retention] = change.proposed
        let now = BrowserDataRetentionClock.now()
        browser.updateDataRetentionPreferences(retention, in: spaceID)
        downloadCenter.sweepExpiredRecords(
            in: browser.spaceModels,
            now: now,
            force: true
        )
        pendingChange = nil
    }
}
