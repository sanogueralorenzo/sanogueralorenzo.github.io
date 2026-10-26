import SwiftUI

/// One Space's settings: its crest and name over a tab bar of its pages.
struct BrowserSettingsSpacePage: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let space: SpaceModel
    let dataDeleter: any BrowserSpaceDataDeleting
    @Bindable var tabState: BrowserSettingsTabState
    let openSpace: BrowserSettingsOpenSpaceAction

    @State private var pendingDeletionID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            tabContent
                .environment(\.browserSettingsScrollKey, "space-\(space.id)-\(tab.name)")
                .id(tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BrowserSettingsCanvas.background)
        .browserSpaceDeletion($pendingDeletionID, browser: browser, dataDeleter: dataDeleter)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            BrowserSpaceIdentityIcon(space: space, size: 26)
            Text(space.settings.name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                BrowserSettingsSpaceMenu(
                    browser: browser, space: space, openSpace: openSpace,
                    requestDeletion: { pendingDeletionID = space.id })
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
        tabs.contains(tabState.spaceTab) ? tabState.spaceTab : .identity
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
        case .identity:
            BrowserSpaceEditorView(
                browser: browser, space: space, dataDeleter: dataDeleter, requestsEditing: renameRequest)
        case .privacy:
            BrowserPrivacySettingsPane(
                browser: browser,
                downloadCenter: pages.downloadCenter,
                permissionCenter: pages.permissionCenter,
                contentBlockingErrorDescription: pages.contentBlockingErrorDescription,
                fixedSpaceID: space.id
            )
        case .extensions:
            BrowserEngineExtensionSettingsPane(browser: browser, spaceID: space.id)
        }
    }

}

/// What can be done to a Space from its sidebar row or its page.
struct BrowserSettingsSpaceMenu: View {
    let browser: BrowserStore
    let space: SpaceModel
    let openSpace: BrowserSettingsOpenSpaceAction
    let requestDeletion: () -> Void

    var body: some View {
        let order = BrowserSpaceOrderActions(browser: browser, spaceID: space.id)
        Button("Rename") { openSpace(space.id, intent: .rename) }
        Divider()
        Button("Move Up", action: order.moveUp).disabled(!order.canMoveUp)
        Button("Move Down", action: order.moveDown).disabled(!order.canMoveDown)
        Divider()
        Button("Delete “\(space.settings.name)”", role: .destructive, action: requestDeletion)
            .disabled(browser.spaceModels.count <= 1 || browser.isDeleting(space.id))
    }

}

extension View {
    /// Deletes the requested Space and its data, reporting a failure.
    func browserSpaceDeletion(
        _ spaceID: Binding<UUID?>,
        browser: BrowserStore,
        dataDeleter: any BrowserSpaceDataDeleting
    ) -> some View {
        modifier(BrowserSpaceDeletion(spaceID: spaceID, browser: browser, dataDeleter: dataDeleter))
    }
}

private struct BrowserSpaceDeletion: ViewModifier {
    @Binding var spaceID: UUID?
    let browser: BrowserStore
    let dataDeleter: any BrowserSpaceDataDeleting
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: spaceID) { _, id in
                if let id { delete(id) }
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
