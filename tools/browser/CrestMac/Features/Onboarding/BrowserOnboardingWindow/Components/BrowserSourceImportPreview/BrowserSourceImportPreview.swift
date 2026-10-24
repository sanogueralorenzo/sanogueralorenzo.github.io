import SwiftUI

struct BrowserSourceImportPreview: View {
    let application: ImportSource?
    let review: BrowserImportSpaceReview
    let overflowTabIDs: Set<UUID>
    let duplicateTabIDs: Set<UUID>
    let duplicateDestinationName: String?
    let setIncluded: (UUID, Bool) -> Void
    let setSectionIncluded: (Set<UUID>, Bool) -> Void
    let setPlacement: (UUID, TabPlacement) -> Void
    /// The icons the Space's extensions wear, by identifier.
    var extensionIcons: [String: NSImage] = [:]
    /// Turns one of the Space's extensions on or off; without it the
    /// extensions only show.
    var setExtensionIncluded: ((String, Bool) -> Void)?
    /// The name of the browser the review brings from.
    var title: String?

    var body: some View {
        BrowserImportSidebarFrame(branding: review.sourceSpace.settings.look) {
            BrowserSourceImportContent(
                application: application,
                review: review,
                sections: BrowserSourceImportPreviewSections(review: review),
                overflowTabIDs: overflowTabIDs,
                duplicateTabIDs: duplicateTabIDs,
                duplicateDestinationName: duplicateDestinationName,
                setIncluded: setIncluded,
                setSectionIncluded: setSectionIncluded,
                setPlacement: setPlacement,
                extensionIcons: extensionIcons,
                setExtensionIncluded: setExtensionIncluded,
                title: title
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(title ?? application?.title ?? "Source browser") \(review.sourceSpace.settings.name) sidebar before import"
        )
    }
}
