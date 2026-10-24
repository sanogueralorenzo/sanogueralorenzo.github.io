import SwiftUI

/// Renames in place: Return or focus loss commits, and Escape cancels.
struct BrowserFolderHeaderControl: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    private var folder: FolderStateModel { configuration.folder }
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @AppStorage(BrowserFolderAppearancePreference.showsTabCountsKey, store: BrowserFolderAppearancePreference.defaults)
    private var showsTabCounts = true
    @AppStorage(BrowserFolderAppearancePreference.alwaysVisibleKey, store: BrowserFolderAppearancePreference.defaults)
    private var alwaysVisible = false
    @AppStorage(BrowserFolderAppearancePreference.tintsTitleKey, store: BrowserFolderAppearancePreference.defaults)
    private var tintsTitle = BrowserLookAndFeelDefaults.foldersTintTitle
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var textScale = 1.0

    private var isEditing: Bool {
        interaction.editingFolderRequest.wrappedValue
            == configuration.folderRuntimeAssignment
    }

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 7) {
                    BrowserFolderIcon(
                        folder: folder,
                        isExpanded: interaction.isExpanded.wrappedValue,
                        metrics: configuration.headerMetrics
                    )

                    TextField("Folder Name", text: interaction.draftTitle)
                        .textFieldStyle(.plain)
                        .focused(interaction.isTitleFocused)
                        .submitLabel(.done)
                        .onSubmit(interaction.commitTitle)
                        .onKeyPress(.escape) {
                            interaction.cancelTitleEditing()
                            return .handled
                        }

                    Spacer(minLength: 8)
                }
                .browserSavedFolderHeaderLayout(configuration: configuration)
            } else {
                Button {
                    guard !sidebarInteraction.sidebarReorderState.suppressesActivation else { return }
                    configuration.browser.tabMultiSelection.click(
                        .folder(folder.id),
                        units: BrowserSidebarSelection.itemUnits(in: configuration.browser))
                    interaction.toggleExpansion()
                } label: {
                    HStack(spacing: 7) {
                        BrowserFolderIcon(
                            folder: folder,
                            isExpanded: interaction.isExpanded.wrappedValue,
                            metrics: configuration.headerMetrics
                        )

                        BrowserFolderHeaderTitle(
                            folder: folder, context: configuration.context, tintsTitle: tintsTitle,
                            emphasizesShownTab: alwaysVisible
                        )
                        .equatable()

                        Spacer(minLength: 8)
                        if showsTabCounts {
                            BrowserFolderTabCount(folder: folder, space: configuration.context.space).equatable()
                        }
                    }
                    .browserSavedFolderHeaderLayout(configuration: configuration)
                    .contentShape(.rect)
                }
                .buttonStyle(BrowserFolderHeaderButtonStyle())
            }
        }
        .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
    }

}

/// The folder's title, in its color where the person asked for it, and bold
/// while the folder holds the shown tab where every folder stays visible. It
/// reads the folder's tabs only for that emphasis, so the rest of the header
/// redraws for neither.
private struct BrowserFolderHeaderTitle: View, @MainActor Equatable {
    let folder: FolderStateModel
    let context: BrowserSidebarListContext
    let tintsTitle: Bool
    let emphasizesShownTab: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(folder.shownTitle)
            .foregroundStyle(
                tintsTitle
                    ? folder.displayColor.folderTitleColor(onDarkBackground: colorScheme == .dark).color
                    : .primary
            )
            .fontWeight(tintsTitle || holdsShownTab ? .semibold : .regular)
            .lineLimit(1)
            .modifier(BrowserFolderTitlePressFeedback())
    }

    private var holdsShownTab: Bool {
        guard emphasizesShownTab else { return false }
        return context.space.tabIDs(inFolder: folder.id).contains { context.window.shownTabIDs.contains($0) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder === rhs.folder && lhs.context == rhs.context && lhs.tintsTitle == rhs.tintsTitle
            && lhs.emphasizesShownTab == rhs.emphasizesShownTab
    }
}

/// How many tabs the folder holds, however deep. It reads the folder's lists,
/// so a tab arriving or leaving redraws this count and not the header.
private struct BrowserFolderTabCount: View, Equatable {
    let folder: FolderStateModel
    let space: SpaceModel

    var body: some View {
        Text(space.tabIDs(inFolder: folder.id).count, format: .number)
            .font(.caption)
            .foregroundStyle(.secondary)
            .modifier(BrowserFolderTitlePressFeedback())
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.folder === rhs.folder && lhs.space === rhs.space
    }
}

extension EnvironmentValues {
    @Entry fileprivate var folderHeaderIsPressed = false
}

/// PlainButtonStyle fades its entire label. Only the title and count acknowledge
/// a press here, keeping the animated artwork's color steady.
private struct BrowserFolderHeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.folderHeaderIsPressed, configuration.isPressed)
    }
}

private struct BrowserFolderTitlePressFeedback: ViewModifier {
    @Environment(\.folderHeaderIsPressed) private var isPressed

    func body(content: Content) -> some View {
        content.opacity(isPressed ? 0.55 : 1)
    }
}
