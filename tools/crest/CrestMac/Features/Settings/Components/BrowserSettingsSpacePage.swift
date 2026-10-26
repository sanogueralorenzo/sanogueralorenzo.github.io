import SwiftUI

/// One Space's settings: its crest and name over a tab bar of its pages.
struct BrowserSettingsSpacePage: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let space: SpaceModel
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    @Bindable var tabState: BrowserSettingsTabState
    let openSpace: BrowserSettingsOpenSpaceAction

    @State private var downloads = BrowserSpaceDownloadSettingsModel()
    @State private var passwordSearchText = ""
    @State private var pendingDeletionID: UUID?
    @State private var showsArtworkCredits = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if spaceAccess.isLocked(space) {
                BrowserSettingsPane(.spaces) {
                    BrowserSettingsPrivateSpaceAccessSection(
                        space: space,
                        accessController: spaceAccess,
                        detail: "Unlock this Space to see its settings."
                    )
                }
            } else {
                tabPicker
                tabContent
                    .environment(\.browserSettingsScrollKey, "space-\(space.id)-\(tab.name)")
                    .id(tab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BrowserSettingsCanvas.background)
        .browserSpaceDeletionConfirmation($pendingDeletionID, browser: browser, dataDeleter: dataDeleter)
        .sheet(isPresented: $showsArtworkCredits) {
            BrowserCrestArtworkCredits()
        }
    }

    /// The look this Space started from, as its house or scheme draws it.
    private var startingAppearance: SpaceBranding? {
        space.settings.look.startingLook
    }

    private func resetAppearance() {
        guard let startingAppearance else { return }
        browser.spaceBrandingBinding(in: space).wrappedValue = startingAppearance
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            BrowserSpaceIdentityIcon(space: space, size: 26)
            BrowserInlineSpaceName(
                name: browser.spaceNameBinding(in: space),
                size: 18,
                titleFont: .title3.weight(.semibold),
                requestsEditing: renameRequest
            )
            .disabled(spaceAccess.isLocked(space))
            Menu {
                BrowserSettingsSpaceMenu(
                    browser: browser, space: space, spaceAccess: spaceAccess, openSpace: openSpace,
                    requestDeletion: { pendingDeletionID = space.id })
                Divider()
                Button("Reset Appearance") { resetAppearance() }
                    .disabled(startingAppearance == nil || startingAppearance == space.settings.look)
                Button("Artwork Credits") { showsArtworkCredits = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Space actions")
            .accessibilityLabel("Space actions")
            .accessibilityIdentifier("space-settings-menu")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-page-header")
    }

    private var renameRequest: Binding<Bool> {
        Binding {
            tabState.renameSpaceID == space.id
        } set: { requested in
            if !requested, tabState.renameSpaceID == space.id { tabState.renameSpaceID = nil }
        }
    }

    // MARK: - Tabs

    private var tabs: [BrowserSpaceSettingsTab] {
        BrowserSpaceSettingsTab.provided(in: browser.core.state)
    }

    /// The tab shown: the one last chosen, while this device offers it.
    private var tab: BrowserSpaceSettingsTab {
        tabs.contains(tabState.spaceTab) ? tabState.spaceTab : .appearance
    }

    private var tabPicker: some View {
        Picker("Page", selection: Binding(get: { tab }, set: { tabState.spaceTab = $0 })) {
            ForEach(tabs) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("space-settings-tabs")
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab.kind {
        case .appearance:
            BrowserSpaceEditorView(browser: browser, space: space)
        case .browsing:
            browsingPane
        case .privacy:
            BrowserPrivacySettingsPane(
                browser: browser,
                downloadCenter: pages.downloadCenter,
                spaceAccess: spaceAccess,
                permissionCenter: pages.permissionCenter,
                contentBlockingErrorDescription: pages.contentBlockingErrorDescription,
                fixedSpaceID: space.id
            )
        case .passwords:
            BrowserPasswordSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                layout: .macOSSpacePage,
                searchText: $passwordSearchText,
                fixedSpaceID: space.id
            )
        case .extensions:
            BrowserEngineExtensionSettingsPane(browser: browser, spaceAccess: spaceAccess, spaceID: space.id)
        }
    }

    /// The Space's browsing, downloads and deletion, with its download
    /// settings read fresh whenever the Space changes.
    private var browsingPane: some View {
        BrowserSettingsPane(.spaces) {
            BrowserSpaceBrowsingSection(browser: browser, space: space)
            BrowserSpaceDownloadsSection(settings: downloads.settings(for: space))
            BrowserSpaceDeletionSection(browser: browser, spaceID: space.id, dataDeleter: dataDeleter)
        }
        .task(id: space.id) { downloads.refresh(for: space.id) }
    }
}

/// Who drew the crest artwork.
private struct BrowserCrestArtworkCredits: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artwork Credits").font(.headline)
            ScrollView {
                Text(BrowserCrestStudioAppearance.credits)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 360)
    }
}

/// What can be done to a Space from its sidebar row or its page.
struct BrowserSettingsSpaceMenu: View {
    let browser: BrowserStore
    let space: SpaceModel
    let spaceAccess: BrowserSpaceAccessController
    let openSpace: BrowserSettingsOpenSpaceAction
    let requestDeletion: () -> Void

    var body: some View {
        let order = BrowserSpaceOrderActions(browser: browser, spaceID: space.id)
        Button("Rename") { openSpace(space.id, intent: .rename) }
        Button("Edit Crest…") { openSpace(space.id, tab: .appearance) }
        Divider()
        Button("Move Up", action: order.moveUp).disabled(!order.canMoveUp)
        Button("Move Down", action: order.moveDown).disabled(!order.canMoveDown)
        Divider()
        Toggle("Lock Space", isOn: lock)
        Divider()
        Button("Delete “\(space.settings.name)”…", role: .destructive, action: requestDeletion)
            .disabled(browser.spaceModels.count <= 1 || browser.isDeleting(space.id))
    }

    private var lock: Binding<Bool> {
        Binding {
            space.settings.requiresAuthentication
        } set: { isRequired in
            Task {
                await spaceAccess.updatePolicy(
                    isRequired ? .deviceOwnerAuthentication : .open,
                    matching: BrowserSpaceRuntimeAssignment(space: space),
                    in: browser
                )
            }
        }
    }
}

extension View {
    /// Asks before deleting the Space `spaceID` names, then deletes it and
    /// its data, reporting a failure.
    func browserSpaceDeletionConfirmation(
        _ spaceID: Binding<UUID?>,
        browser: BrowserStore,
        dataDeleter: any BrowserSpaceDataDeleting
    ) -> some View {
        modifier(BrowserSpaceDeletionConfirmation(spaceID: spaceID, browser: browser, dataDeleter: dataDeleter))
    }
}

private struct BrowserSpaceDeletionConfirmation: ViewModifier {
    @Binding var spaceID: UUID?
    let browser: BrowserStore
    let dataDeleter: any BrowserSpaceDataDeleting
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .alert(
                "Delete “\(spaceName)”?",
                isPresented: Binding(get: { spaceID != nil }, set: { if !$0 { spaceID = nil } }),
                presenting: spaceID
            ) { id in
                Button("Delete Space and Data", role: .destructive) { delete(id) }
                    .accessibilityIdentifier("confirm-delete-space")
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(
                    "This permanently removes this Space’s browser data from Crest. "
                        + "Downloaded files you already saved are kept."
                )
            }
            .alert(
                "Couldn’t Delete Space",
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private var spaceName: String {
        spaceID.flatMap(browser.spaceModel)?.settings.name ?? "Space"
    }

    private func delete(_ id: UUID) {
        spaceID = nil
        Task { @MainActor in
            do {
                try await browser.deleteSpace(id, dataDeleter: dataDeleter)
            } catch {
                failure = "\(error.localizedDescription) The Space was kept so you can try again."
            }
        }
    }
}
