import SwiftUI

/// The Settings pane list: a search field over the platform's own sidebar list,
/// grouped the way the macOS catalog orders it, with the Spaces between the
/// last two groups.
struct BrowserSettingsSidebar: View {
    @Environment(\.locale) private var locale
    @State private var standaloneScroll = BrowserNativeScrollState()
    @State private var pendingDeletionID: UUID?
    @State private var hoveredItem: BrowserSettingsSidebarItem?
    @Bindable var tabState: BrowserSettingsTabState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let openSpace: BrowserSettingsOpenSpaceAction
    let addSpace: () -> Void
    @FocusState private var isSearchFocused: Bool

    private var navigation: BrowserSettingsNavigationState { tabState.navigation }
    private var state: CoreState { browser.core.state }

    var body: some View {
        VStack(spacing: 0) {
            BrowserSettingsBuildHeader()
            searchField
            List(selection: selection) {
                if let first = visibleGroups.first {
                    destinationSection(first)
                }
                spacesSection
                ForEach(Array(visibleGroups.dropFirst().enumerated()), id: \.offset) { _, group in
                    destinationSection(group)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .browserNativeScrollState(tabState.sidebarScroll)
        }
        .background(BrowserSettingsCanvas.background)
        .browserSpaceDeletionConfirmation($pendingDeletionID, browser: browser, dataDeleter: dataDeleter)
        .onChange(of: navigation.query.isEmpty) { _, isEmpty in
            if !isEmpty { tabState.isArrangingSpaces = false }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search settings", text: $tabState.navigation.searchText)
                .textFieldStyle(.plain).focused($isSearchFocused)
            if !navigation.searchText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { tabState.navigation.searchText = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Destinations

    private func destinationSection(_ group: [BrowserSettingsDestination]) -> some View {
        Section {
            ForEach(group) { destination in
                Label {
                    Text(destination.navigationTitle)
                } icon: {
                    Image(systemName: destination.symbol)
                        .foregroundStyle(destination.sidebarTint)
                }
                .settingsSidebarRow(.destination(destination), hovered: $hoveredItem, selection: selection)
                .accessibilityIdentifier("settings-\(destination.name)")
            }
        }
    }

    /// The catalog's groups, keeping only the destinations the search shows.
    private var visibleGroups: [[BrowserSettingsDestination]] {
        let visible = Set(navigation.visibleDestinations(locale: locale, in: state))
        return BrowserPlatformSettingsDestinationCatalog.groups
            .map { group in group.filter(visible.contains) }
    }

    // MARK: - Spaces

    @ViewBuilder
    private var spacesSection: some View {
        let spaces = visibleSpaces
        if !spaces.isEmpty || navigation.query.isEmpty {
            Section {
                ForEach(spaces) { space in
                    spaceRow(space)
                }
                .onMove { source, destination in
                    browser.moveSpaces(from: source, to: destination)
                }
            } header: {
                spacesHeader
            }
        }
    }

    private var spacesHeader: some View {
        HStack(spacing: BrowserSettingsSidebarMetrics.headerButtonSpacing) {
            Text("Spaces")
            Spacer(minLength: 4)
            if navigation.query.isEmpty {
                let arranging = tabState.isArrangingSpaces
                Button {
                    tabState.isArrangingSpaces.toggle()
                } label: {
                    Image(systemName: arranging ? "checkmark" : "pencil")
                        .foregroundStyle(arranging ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .help(arranging ? "Done" : "Rearrange Spaces")
                .accessibilityLabel(arranging ? "Done" : "Rearrange Spaces")
                .accessibilityIdentifier("settings-spaces-arrange")
                .disabled(browser.spaceModels.count < 2 && !arranging)

                Button(action: addSpace) {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
                .help("Add Space")
                .accessibilityLabel("Add Space")
                .accessibilityIdentifier("settings-spaces-add")
            }
        }
        .buttonStyle(CrestChromeButtonStyle(controlSize: BrowserSettingsSidebarMetrics.headerButtonSize))
        .font(.system(size: 12, weight: .medium))
        .padding(.trailing, BrowserSettingsSidebarMetrics.headerTrailingInset)
        .accessibilityElement(children: .contain)
    }

    private func spaceRow(_ space: SpaceModel) -> some View {
        HStack(spacing: 6) {
            Label {
                Text(space.settings.name.isEmpty ? String(localized: "Untitled Space") : space.settings.name)
                    .lineLimit(1)
            } icon: {
                BrowserSpaceIdentityIcon(space: space, size: 18)
            }
            Spacer(minLength: 4)
            if tabState.isArrangingSpaces {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Drag to reorder")
            } else {
                if space.settings.requiresAuthentication {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Locked")
                }
                if navigation.selection == .space(space.id) {
                    Menu {
                        spaceMenu(space)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Space actions")
                    .accessibilityLabel("Space actions")
                }
            }
        }
        .settingsSidebarRow(.space(space.id), hovered: $hoveredItem, selection: selection)
        .moveDisabled(!tabState.isArrangingSpaces)
        .contextMenu { spaceMenu(space) }
        .accessibilityIdentifier("settings-space-\(space.id)")
    }

    private func spaceMenu(_ space: SpaceModel) -> some View {
        BrowserSettingsSpaceMenu(
            browser: browser, space: space, spaceAccess: spaceAccess, openSpace: openSpace,
            requestDeletion: { pendingDeletionID = space.id })
    }

    /// Every Space while arranging; otherwise the Spaces the search shows.
    private var visibleSpaces: [SpaceModel] {
        let spaces = browser.spaceModels.filter { !browser.isDeleting($0.id) }
        guard !tabState.isArrangingSpaces else { return spaces }
        let tab = navigation.matchingSpaceTab(locale: locale, in: state)
        return spaces.filter { navigation.lists($0, spaceTab: tab) }
    }

    // MARK: - Selection

    /// The list's selection. A page without a row selects the row it lives
    /// under; clearing the selection is ignored, so a pane is always shown.
    private var selection: Binding<BrowserSettingsSidebarItem?> {
        Binding {
            navigation.selection.row
        } set: { item in
            item?.select(on: tabState) { id in
                openSpace(id, tab: navigation.matchingSpaceTab(locale: locale, in: state))
            }
        }
    }
}

extension View {
    /// A sidebar row for `item`, wearing Crest's hover surface while the
    /// pointer is over it unless it is the selected row.
    fileprivate func settingsSidebarRow(
        _ item: BrowserSettingsSidebarItem,
        hovered: Binding<BrowserSettingsSidebarItem?>,
        selection: Binding<BrowserSettingsSidebarItem?>
    ) -> some View {
        let isHovered = hovered.wrappedValue == item && selection.wrappedValue != item
        return
            self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onHover { inside in
                if inside {
                    hovered.wrappedValue = item
                } else if hovered.wrappedValue == item {
                    hovered.wrappedValue = nil
                }
            }
            .listRowBackground(
                Color.clear
                    .crestInteractiveSurface(isSelected: false, isHovering: isHovered)
                    .padding(.horizontal, BrowserSettingsSidebarMetrics.rowHighlightInset)
            )
            .tag(item)
    }
}

private enum BrowserSettingsSidebarMetrics {
    /// Matches the inset of the sidebar's own selection highlight.
    static let rowHighlightInset: CGFloat = 10
    static let headerButtonSpacing: CGFloat = 4
    /// Lines the header's buttons up with the trailing glyphs of the rows.
    static let headerTrailingInset: CGFloat = 6
    static let headerButtonSize = CGSize(width: 22, height: 22)
}
