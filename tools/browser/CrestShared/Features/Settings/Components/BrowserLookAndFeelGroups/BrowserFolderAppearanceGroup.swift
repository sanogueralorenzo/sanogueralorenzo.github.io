import SwiftUI

/// How folders read in every Space on this device. A Space's own folder color
/// travels with its branding and stays in the Space editor.
struct BrowserFolderAppearanceGroup: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @AppStorage(BrowserFolderAppearancePreference.alwaysVisibleKey, store: BrowserFolderAppearancePreference.defaults)
    private var alwaysVisible = BrowserLookAndFeelDefaults.foldersAlwaysVisible
    @AppStorage(BrowserFolderAppearancePreference.showsTabCountsKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsTabCounts = BrowserLookAndFeelDefaults.foldersShowTabCounts
    @AppStorage(BrowserFolderAppearancePreference.showsBordersKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsBorders = BrowserLookAndFeelDefaults.foldersShowBorders
    @AppStorage(BrowserFolderAppearancePreference.iconOnlyKey, store: BrowserFolderAppearancePreference.defaults)
    private var iconOnly = BrowserLookAndFeelDefaults.foldersIconOnly
    @AppStorage(BrowserFolderAppearancePreference.tintsTitleKey, store: BrowserFolderAppearancePreference.defaults)
    private var tintsTitle = BrowserLookAndFeelDefaults.foldersTintTitle

    var body: some View {
        CrestSettingsGroup(
            "Folders",
            settings: settings
        ) {
            if showsPreview {
                BrowserLookAndFeelPreview(space: space, focus: .folders)
            }
        } content: {
            CrestSettingRow("Icon Only Folders", setting: icons.resettable("Icon Only Folders")) {
                Toggle("Icon Only Folders", isOn: icons.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-icon-only")
                    .help("Show a static custom icon or emoji instead of folder artwork.")
            }
            CrestSettingRow("Tint Folder Title", setting: titles.resettable("Tint Folder Title")) {
                Toggle("Tint Folder Title", isOn: titles.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-tint-title")
            }
            CrestSettingRow(
                "Always show folder highlights", setting: highlights.resettable("Always show folder highlights")
            ) {
                Toggle("Always show folder highlights", isOn: highlights.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-always-show-highlights")
            }
            CrestSettingRow("Show folder tab counts", setting: counts.resettable("Show folder tab counts")) {
                Toggle("Show folder tab counts", isOn: counts.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-show-tab-counts")
            }
            CrestSettingRow("Show folder color borders", setting: borders.resettable("Show folder color borders")) {
                Toggle("Show folder color borders", isOn: borders.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("folder-show-color-borders")
            }
        }
    }

    private var highlights: CrestSettingValue<Bool> {
        CrestSettingValue($alwaysVisible, default: BrowserLookAndFeelDefaults.foldersAlwaysVisible)
    }

    private var counts: CrestSettingValue<Bool> {
        CrestSettingValue($showsTabCounts, default: BrowserLookAndFeelDefaults.foldersShowTabCounts)
    }

    private var borders: CrestSettingValue<Bool> {
        CrestSettingValue($showsBorders, default: BrowserLookAndFeelDefaults.foldersShowBorders)
    }

    private var settings: [CrestResettableSetting] {
        [
            icons.resettable("Icon Only Folders"),
            titles.resettable("Tint Folder Title"),
            highlights.resettable("Always show folder highlights"),
            counts.resettable("Show folder tab counts"),
            borders.resettable("Show folder color borders"),
        ]
    }

    private var icons: CrestSettingValue<Bool> {
        CrestSettingValue($iconOnly, default: BrowserLookAndFeelDefaults.foldersIconOnly)
    }

    private var titles: CrestSettingValue<Bool> {
        CrestSettingValue($tintsTitle, default: BrowserLookAndFeelDefaults.foldersTintTitle)
    }
}
