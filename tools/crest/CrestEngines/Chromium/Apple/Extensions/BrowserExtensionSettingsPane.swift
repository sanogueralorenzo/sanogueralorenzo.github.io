import SwiftUI

struct BrowserExtensionSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    /// The one Space whose extensions the pane shows, or nil to pick one.
    var fixedSpaceID: UUID?
    @State private var selectedSpaceID: UUID?
    private var store: ChromiumExtensionStore { ChromiumComposition.extensions }
    private var space: BrowserSpaceIdentity? {
        browser.spaceModel(fixedSpaceID ?? selectedSpaceID ?? browser.selectedSpaceID)?.identity
    }

    var body: some View {
        BrowserSettingsPane(.extensions) {
            if fixedSpaceID == nil {
                Section {
                    CrestSpaceMenuPicker(
                        "Space", selection: $selectedSpaceID,
                        spaces: CrestSpaceIdentity.list(browser.spaceModels))
                }
            }
            if let space, !spaceAccess.isLocked(space) {
                BrowserExtensionsView(space: space, store: store).id(space.profileID)
            } else if let space {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: space, accessController: spaceAccess,
                    detail: "Unlock this Space to see its extensions.")
            }
        }
        .onAppear { if selectedSpaceID == nil { selectedSpaceID = browser.selectedSpaceID } }
        .onChange(of: browser.spaceModels.map(\.id)) {
            if !browser.spaceModels.contains(where: { $0.id == selectedSpaceID }) {
                selectedSpaceID = browser.selectedSpaceID
            }
        }
    }
}

struct BrowserExtensionsView: View {
    let space: BrowserSpaceIdentity
    let store: ChromiumExtensionStore
    @State private var failure: String?
    @State private var pendingRemoval: ChromiumExtensionStore.Installed?
    @State private var pendingCopy: ChromiumExtensionStore.Installed?
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    private var extensions: [ChromiumExtensionStore.Installed] {
        (store.installed[space.profileID] ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var body: some View {
        Group {
            if !usesLiveSidebar { installedExtensions }
            Section("Add extensions") {
                HStack(spacing: 12) {
                    Button("Open Chrome Web Store") { run(.store) }
                    Button("Chromium Extension Manager") { run(.manage) }
                    Spacer(minLength: 0)
                    // Extension shortcuts are the engine's own bindings: Crest routes an
                    // unclaimed key equivalent to them but does not own their list.
                    Button("Shortcuts…") { run(.shortcuts) }
                }
            }
            if usesLiveSidebar { installedExtensions }
        }
        .task(id: space.profileID) { await store.load(space) }
        .alert(
            "Couldn’t Complete Extension Action",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
        .confirmationDialog(
            "Remove Extension?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { item in
            Button("Remove from \(space.name)", role: .destructive) {
                run(.remove, item.id)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { item in
            Text("\(item.name) and its data are removed from this Space only.")
        }
        .sheet(item: $pendingCopy) { item in BrowserExtensionCopySheet(item: item, space: space, store: store) }
    }
    private var installedExtensions: some View {
        Section("Installed") {
            if store.installed[space.profileID] == nil {
                ProgressView()
            } else if extensions.isEmpty {
                Text("No extensions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(extensions) { item in
                    BrowserExtensionRow(
                        item: item, setEnabled: { run($0 ? .enable : .disable, item.id) },
                        options: { run(.options, item.id) }, manage: { run(.details, item.id) },
                        remove: { pendingRemoval = item }, copy: { pendingCopy = item })
                }
            }
        }
    }
    private func run(_ command: ExtensionCommand, _ id: String = "") {
        if !store.command(command, extensionID: id, space: space) {
            failure = "Check the extension’s details for policy or permission requirements."
        }
    }
}

/// Preserves Crest's disclosure row, artwork, version, description, and toggle.
struct BrowserExtensionRow: View {
    let item: ChromiumExtensionStore.Installed
    let setEnabled: @MainActor @Sendable (Bool) -> Void
    let options: () -> Void
    let manage: () -> Void
    let remove: () -> Void
    let copy: () -> Void
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                if item.webStore { Button("Install a copy in other spaces", action: copy) }
                if !item.permissions.isEmpty {
                    VStack(alignment: .leading, spacing: CrestSpacing.small) {
                        Text("Permissions and Website Access").font(.headline)
                        ForEach(item.permissions, id: \.self) {
                            Text($0).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button("Manage Permissions in Chromium", systemImage: "hand.raised", action: manage)
                if !item.options.isEmpty && item.enabled {
                    Button("Extension Settings", systemImage: "gearshape", action: options)
                }
                Button("Remove Extension", systemImage: "trash", role: .destructive, action: remove)
            }
            .padding(.top, CrestSpacing.medium)
            .padding(.leading, BrowserExtensionsMetrics.expandedContentIndent)
        } label: {
            HStack(alignment: .center, spacing: CrestSpacing.medium) {
                BrowserExtensionIconView(image: item.icon)
                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    HStack(spacing: CrestSpacing.small) {
                        Text(item.name).font(.body.weight(.medium))
                        Text(item.version).font(.caption).foregroundStyle(.tertiary)
                    }
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    if item.webStore {
                        Text("From Chrome Web Store").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Toggle("Enabled", isOn: Binding(get: { item.enabled }, set: setEnabled))
                    .labelsHidden().accessibilityLabel("\(item.name) Enabled")
            }
        }.padding(.vertical, CrestSpacing.extraSmall)
    }
}

struct BrowserExtensionCopySheet: View {
    let item: ChromiumExtensionStore.Installed
    let space: BrowserSpaceIdentity
    let store: ChromiumExtensionStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSpaces: Set<UUID> = []
    @State private var loading = true
    private var destinations: [BrowserSpaceIdentity] {
        store.spaces.filter {
            $0.id != space.id && !(store.installed[$0.profileID] ?? []).contains { $0.id == item.id }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            Text("Install a Copy in Other Spaces").font(.title2.bold())
            Text(item.name).font(.headline)
            Text(
                "Each Space keeps its own extension data; existing data is not copied. Review the verified package and permissions before installing."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            BrowserExtensionSpaceSelectionList(spaces: destinations, selection: $selectedSpaces).disabled(loading)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button("Review Installation") {
                    let targets = destinations.filter { selectedSpaces.contains($0.id) }
                    guard let first = targets.first else { return }
                    dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        store.install(item.id, in: first, anchor: nil, copies: Set(targets.dropFirst().map(\.id)))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading || selectedSpaces.intersection(Set(destinations.map(\.id))).isEmpty)
            }
        }
        .padding(CrestSpacing.extraLarge)
        .frame(idealWidth: 480)
        .task {
            for target in store.spaces { await store.load(target) }
            loading = false
        }
    }
}
