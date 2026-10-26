import SwiftUI

struct BrowserShortcutList: View {
    let model: BrowserShortcutSettingsModel
    @Environment(\.browserSettingsTabState) private var tabState
    @State private var standaloneScroll = BrowserNativeScrollState()

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.commandGroups) { group in
                    Section {
                        ForEach(group.commands) { command in
                            BrowserShortcutRow(
                                command: command,
                                shortcut: model.shortcut(for: command),
                                isCustomized: model.isCustomized(command),
                                record: { model.record($0, for: command) },
                                reset: { model.reset(command) },
                                reportInvalidShortcut:
                                    model.reportInvalidShortcut
                            )
                        }
                    } header: {
                        Text(group.section.title)
                    }
                }

            }
            .browserNativeListScrollState(tabState?.scroll(for: .shortcuts) ?? standaloneScroll)
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if model.commandGroups.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
            .accessibilityIdentifier(
                BrowserShortcutSettingsAccessibilityID.list
            )
        }
    }

}

private struct BrowserShortcutRow: View {
    @Environment(\.locale) private var locale

    let command: ShortcutCommand
    let shortcut: BrowserShortcut?
    let isCustomized: Bool
    let record: (BrowserShortcut?) -> Void
    let reset: () -> Void
    let reportInvalidShortcut: () -> Void

    var body: some View {
        HStack(spacing: BrowserShortcutSettingsMetrics.rowSpacing) {
            Text(command.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCustomized {
                Text(BrowserShortcutSettingsPresentation.custom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            BrowserShortcutRecorder(
                identifier: command.name,
                title: command.title(locale: locale),
                shortcut: shortcut,
                record: record,
                reportInvalidShortcut: reportInvalidShortcut
            )
            .frame(
                width: BrowserShortcutSettingsMetrics.recorderWidth,
                height: BrowserShortcutSettingsMetrics.recorderHeight
            )

            Menu {
                Group {
                    Button(
                        BrowserShortcutSettingsPresentation.clearShortcut,
                        systemImage: "delete.left"
                    ) {
                        record(nil)
                    }
                    .disabled(shortcut == nil)
                    Button(
                        BrowserShortcutSettingsPresentation.resetToDefault,
                        systemImage: "arrow.counterclockwise",
                        action: reset
                    )
                    .disabled(!isCustomized)
                }
                .crestMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(
                        width: BrowserShortcutSettingsMetrics.actionSize,
                        height: BrowserShortcutSettingsMetrics.actionSize
                    )
                    .contentShape(.rect)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .crestMenuActionLabelStyle()
            .fixedSize()
            .help(Text(BrowserShortcutSettingsPresentation.shortcutActions))
            .accessibilityLabel(
                Text(
                    BrowserShortcutSettingsPresentation
                        .actionsAccessibilityLabel(
                            title: command.title(locale: locale)
                        )
                )
            )
        }
        .padding(
            .vertical,
            BrowserShortcutSettingsMetrics.rowVerticalPadding
        )
        .accessibilityElement(children: .contain)
    }
}
