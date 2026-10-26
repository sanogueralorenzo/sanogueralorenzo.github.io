import SwiftUI

/// An app icon as the Home Screen draws it, in its light or dark rendition.
/// The system renders an Icon Composer icon only for the Home Screen, so each
/// icon ships a rendering of itself as `<name>Preview`, already cut to the
/// icon's rounded square.
struct BrowserPlatformAppIcon: View {
    // MARK: - Static Variables

    /// The primary icon's name, which `ASSETCATALOG_COMPILER_APPICON_NAME`
    /// sets.
    private static let primaryName = "Crest"

    // MARK: - Variables

    /// An alternate icon's name, or nil for Crest's own.
    let name: String?

    var body: some View {
        Image((name ?? Self.primaryName) + "Preview")
            .resizable()
            .scaledToFit()
    }
}
