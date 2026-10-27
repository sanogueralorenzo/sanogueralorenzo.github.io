import SwiftUI
import WebKit

struct BrowserSpaceSettings: View {
    let store: BrowserStore
    let spaceID: UUID
    @State private var pendingRetention:
        (WritableKeyPath<BrowserSpacePreferences, BrowserDataRetention>, BrowserDataRetention)?
    @State private var confirmsReset = false

    private var space: BrowserSpace? { store.session.spaces.first { $0.id == spaceID } }

    var body: some View {
        if let space {
            VStack(spacing: 0) {
                Picker(
                    "Page",
                    selection: Binding(get: { store.settingsSpacePrivacy }, set: { store.settingsSpacePrivacy = $0 })
                ) {
                    Text("Identity").tag(false)
                    Text("Privacy").tag(true)
                }.pickerStyle(.segmented).fixedSize().padding(12)
                BrowserSettingsForm {
                    if store.settingsSpacePrivacy {
                        privacy(space)
                    } else {
                        identity(space)
                    }
                }
            }
            .confirmationDialog(
                "Permanently delete older records?",
                isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })
            ) {
                if let pendingRetention {
                    Button("Use \(pendingRetention.1.title)", role: .destructive) {
                        store.updateSpacePreferences(spaceID) { $0[keyPath: pendingRetention.0] = pendingRetention.1 }
                        self.pendingRetention = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingRetention = nil }
            } message: {
                Text("This permanently removes older records in this Space. Downloaded files stay on disk.")
            }
            .confirmationDialog("Reset All", isPresented: $confirmsReset) {
                Button("Reset All", role: .destructive) {
                    guard let index = store.session.spaces.firstIndex(where: { $0.id == spaceID }) else { return }
                    store.session.spaces[index].permissions = []
                    store.changed()
                }
            } message: {
                Text("Makes every site ask again in this Space")
            }
        } else {
            ContentUnavailableView("Space removed", systemImage: "circle.dashed")
        }
    }

    @ViewBuilder private func identity(_ space: BrowserSpace) -> some View {
        Section("Identity") {
            TextField(
                "Space name",
                text: Binding(
                    get: { self.space?.name ?? "" },
                    set: {
                        store.saveSpace(id: spaceID, name: $0, color: self.space?.color ?? 0)
                    }))
            LabeledContent("Space color") {
                HStack(spacing: 8) {
                    ForEach(0..<6) { index in
                        Button {
                            store.saveSpace(id: spaceID, name: self.space?.name ?? "Space", color: index)
                        } label: {
                            Circle().fill(Color.space(index)).frame(width: 22, height: 22).padding(3)
                                .overlay { if space.color == index { Circle().stroke(.primary, lineWidth: 1) } }
                        }.buttonStyle(.plain).accessibilityLabel(SpaceColors.names[index])
                    }
                }
            }
        }
        Section {
            Button("Delete “\(space.name)”", role: .destructive) { store.deleteSpace(spaceID) }
                .disabled(!space.isPrivate && store.session.spaces.filter { !$0.isPrivate }.count == 1)
            if !space.isPrivate && store.session.spaces.filter({ !$0.isPrivate }).count == 1 {
                Text("Lean needs at least one Space.").foregroundStyle(.secondary)
            }
        }
        // Keep Lean's existing download controls available alongside the Space they affect.
        Section("Downloads") {
            Toggle(
                "Ask Where to Save Each File",
                isOn: Binding(
                    get: { store.preferences.downloadsAskEveryTime },
                    set: { value in store.updatePreferences { $0.downloadsAskEveryTime = value } }))
            Button("Download Folder for This Space…") { store.chooseDownloadDirectory(in: spaceID) }
        }
    }

    @ViewBuilder private func privacy(_ space: BrowserSpace) -> some View {
        Section {
            retention("History", \.historyRetention)
            retention("Archived Tabs", \.archiveRetention)
            retention("Download Records", \.downloadRetention)
        } header: {
            Text("Keep")
        } footer: {
            Text("Removing download records doesn’t delete the files.")
        }
        Section("Content blocking") {
            Toggle(
                "Block known ads and trackers",
                isOn: Binding(
                    get: { store.spacePreferences(spaceID).blocksContent },
                    set: { value in store.updateSpacePreferences(spaceID) { $0.blocksContent = value } }
                ))
        }
        Section("Site permissions") {
            if space.permissions.isEmpty { Text("No saved permissions").foregroundStyle(.secondary) }
            ForEach(space.permissions) { permission in
                LabeledContent {
                    Picker(
                        permission.kind.label,
                        selection: Binding(
                            get: { store.permission(permission.kind, origin: permission.origin, spaceID: spaceID) },
                            set: {
                                store.setPermission(
                                    permission.kind, origin: permission.origin, spaceID: spaceID, decision: $0)
                            }
                        )
                    ) {
                        ForEach(BrowserSitePermission.Decision.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }.labelsHidden()
                } label: {
                    Text(permission.origin)
                    Text(permission.kind.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !space.permissions.isEmpty { Button("Reset All…", role: .destructive) { confirmsReset = true } }
        }
        Section("Browsing data") {
            Button("Clear History in This Space") {
                store.session.history.removeAll { $0.spaceID == spaceID }
                store.changed()
            }
            Button("Clear Website Data in This Space", role: .destructive) {
                store.profile(for: spaceID).removeData(
                    ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
                ) {
                    Task { @MainActor in store.showNotice("Website data cleared") }
                }
            }
        }
    }

    private func retention(_ title: String, _ keyPath: WritableKeyPath<BrowserSpacePreferences, BrowserDataRetention>)
        -> some View
    {
        Picker(
            title,
            selection: Binding(
                get: { store.spacePreferences(spaceID)[keyPath: keyPath] },
                set: { value in
                    let old = store.spacePreferences(spaceID)[keyPath: keyPath]
                    if value != .forever && (old == .forever || value.rawValue < old.rawValue) {
                        pendingRetention = (keyPath, value)
                    } else {
                        store.updateSpacePreferences(spaceID) { $0[keyPath: keyPath] = value }
                    }
                })
        ) {
            ForEach(BrowserDataRetention.allCases) { Text($0.title).tag($0) }
        }
    }
}
