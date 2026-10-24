import SwiftUI

/// The shared Window group. Touch has no window transparency or page motion of
/// its own to add to it.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    var body: some View {
        BrowserWindowAppearanceGroup(space: space, showsPreview: showsPreview) { EmptyView() }
    }
}
