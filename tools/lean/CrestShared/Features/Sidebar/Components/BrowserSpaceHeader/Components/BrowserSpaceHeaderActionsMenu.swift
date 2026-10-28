import SwiftUI

/// A native menu entry shared by the platform presentations.
struct BrowserSpaceHeaderMenuItem {
    var title: LocalizedStringResource
    var symbol: String
    var action: () -> Void = {}
    var shortcut: BrowserShortcut?
    var identifier: String?
    var isEnabled = true
    var isDestructive = false
    var children: [BrowserSpaceHeaderMenuItem] = []
}

/// The Space header's overflow menu, using the shell's available actions.
struct BrowserSpaceHeaderActionsMenu: View {
    // MARK: - Variables

    let isPrivateBrowsing: Bool
    let metrics: BrowserSpaceHeaderMetrics
    let actions: BrowserSpaceHeaderActions

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.browserShortcutBindings) private var shortcutBindings

    // MARK: - Actions - Drawing

    var body: some View {
        styledMenu
            .tint(.primary)
            .help("Space Actions")
            .accessibilityIdentifier("space-actions")
            .accessibilityLabel("Space actions")
    }

    @ViewBuilder
    private var styledMenu: some View {
        #if os(macOS)
            BrowserPlatformSpaceActionsMenu(
                sections: sections, controlSize: metrics.actionsControlSize,
                symbolSize: metrics.actionsGlyph?.size ?? metrics.iconSize
            )
            .fixedSize()
            .offset(y: -CrestSpacing.small)
        #else
            Menu {
                ForEach(sections.indices, id: \.self) { section in
                    if section > 0 { Divider() }
                    ForEach(sections[section].indices, id: \.self) { index in
                        item(sections[section][index])
                    }
                }
                .crestMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(metrics.actionsGlyph?.font)
                    .frame(width: metrics.actionsControlSize, height: metrics.actionsControlSize)
                    .contentShape(.rect)
            }
            .crestMenuActionLabelStyle()
        #endif
    }

    #if !os(macOS)
        @ViewBuilder
        private func item(_ entry: BrowserSpaceHeaderMenuItem) -> some View {
            if entry.children.isEmpty {
                Button(
                    String(localized: entry.title), systemImage: entry.symbol,
                    role: entry.isDestructive ? .destructive : nil,
                    action: entry.action
                )
                .keyboardShortcut(entry.shortcut?.keyboardShortcut)
                .crestAccessibilityIdentifier(entry.identifier)
                .disabled(!entry.isEnabled)
            } else {
                Menu(String(localized: entry.title), systemImage: entry.symbol) {
                    ForEach(entry.children.indices, id: \.self) { index in
                        let child = entry.children[index]
                        Button(String(localized: child.title), action: child.action)
                    }
                }
                .disabled(!entry.isEnabled)
            }
        }
    #endif

    // MARK: - Actions - Entries

    private var sections: [[BrowserSpaceHeaderMenuItem]] {
        var sections: [[BrowserSpaceHeaderMenuItem]] = []
        if let showTabs = actions.showTabs {
            sections.append([.init(title: "Back to Tabs", symbol: "sidebar.left", action: showTabs)])
        }
        if let showWebsiteSettings = actions.showWebsiteSettings {
            sections.append([
                .init(
                    title: "Website Settings", symbol: "slider.horizontal.3", action: showWebsiteSettings,
                    identifier: "website-settings")
            ])
        }

        var creation: [BrowserSpaceHeaderMenuItem] = [
            .init(title: "New Tab", symbol: "plus", action: actions.openNewTab, shortcut: shortcut(for: .newTab))
        ]
        if let openNewWindow = actions.openNewWindow, supportsMultipleWindows {
            creation.append(
                .init(
                    title: "New Window", symbol: "macwindow.badge.plus", action: openNewWindow,
                    shortcut: shortcut(for: .newWindow), identifier: "new-browser-window"))
        }
        creation.append(.init(title: "New Folder", symbol: "folder.badge.plus", action: actions.createFolder))
        if let createGitHubFolder = actions.createGitHubFolder {
            creation.append(
                .init(
                    title: "Live Folder", symbol: "folder.badge.gearshape", isEnabled: !isPrivateBrowsing,
                    children: [
                        .init(title: "GitHub", symbol: "", action: createGitHubFolder)
                    ]))
        }
        sections.append(creation)

        var utilities: [BrowserSpaceHeaderMenuItem] = []
        if let showArchive = actions.showArchive {
            utilities.append(
                .init(
                    title: "Archive", symbol: "archivebox", action: showArchive, shortcut: shortcut(for: .showArchive)))
        }
        utilities.append(
            .init(
                title: "History", symbol: "clock.arrow.circlepath", action: actions.showHistory,
                shortcut: shortcut(for: .showHistory)))
        if let showDownloads = actions.showDownloads {
            utilities.append(
                .init(
                    title: "Downloads", symbol: "arrow.down.circle", action: showDownloads,
                    shortcut: shortcut(for: .showDownloads)))
        }
        sections.append(utilities)

        var settings: [BrowserSpaceHeaderMenuItem] = []
        if isPrivateBrowsing, let closePrivateBrowsing = actions.closePrivateBrowsing {
            settings.append(
                .init(
                    title: "Close Private Tabs", symbol: "xmark.square", action: closePrivateBrowsing,
                    identifier: "close-private-tabs", isDestructive: true))
        }
        if let showSettings = actions.showSettings {
            settings.append(
                .init(
                    title: "Settings", symbol: "gearshape", action: showSettings, shortcut: actions.settingsShortcut,
                    identifier: "settings-button"))
        }
        if !settings.isEmpty { sections.append(settings) }
        return sections
    }

    private func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        command.shortcut(in: shortcutBindings)
    }
}
