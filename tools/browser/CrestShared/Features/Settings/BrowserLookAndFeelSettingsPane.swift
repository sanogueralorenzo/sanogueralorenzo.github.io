import SwiftUI

/// Device appearance edits the visible sidebar in a browser tab. Sheets retain
/// detached component previews because their browser is covered.
struct BrowserLookAndFeelSettingsPane: View {
    var space: BrowserSpaceAppearance? = nil
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(alignment: .top, spacing: 0) {
                if usesLiveSidebar {
                    form(showsInlinePreviews: false)
                        .frame(maxWidth: .infinity)
                } else if let columns = BrowserLookAndFeelColumns(width: width) {
                    BrowserLookAndFeelPreview(space: space, focus: .window, fillsHeight: true)
                        .frame(width: columns.preview)
                        .padding(.leading, BrowserLookAndFeelColumns.previewLeadingPadding)
                        .padding(.vertical, CrestSpacing.extraLarge)
                    form(showsInlinePreviews: false)
                        .frame(width: columns.form)
                } else {
                    form(showsInlinePreviews: true)
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private func form(showsInlinePreviews: Bool) -> some View {
        BrowserSettingsPane(.lookAndFeel) {
            BrowserPlatformAppearanceSettingsSection(space: space, showsPreview: showsInlinePreviews)
            if !usesLiveSidebar {
                BrowserDefaultPageZoomSettingsSection(
                    preferences: .shared, space: space, showsPreview: showsInlinePreviews)
            }
            BrowserTabAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            BrowserTabStatusAppearanceGroup()
            BrowserAddressAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            BrowserFolderAppearanceGroup(space: space, showsPreview: showsInlinePreviews)
            if usesLiveSidebar {
                BrowserDefaultPageZoomSettingsSection(preferences: .shared, space: space, showsPreview: false)
            }
            BrowserPlatformAppIconSettingsSection()
            BrowserPlatformLookAndFeelResetSection()
        }
    }
}
