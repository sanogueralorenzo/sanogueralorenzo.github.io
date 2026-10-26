import SwiftUI

struct BrowserSourceImportContent: View {
    let application: ImportSource?
    let review: BrowserImportSpaceReview
    let sections: BrowserSourceImportPreviewSections
    let overflowTabIDs: Set<UUID>
    let duplicateTabIDs: Set<UUID>
    let duplicateDestinationName: String?
    let setIncluded: (UUID, Bool) -> Void
    let setSectionIncluded: (Set<UUID>, Bool) -> Void
    let setPlacement: (UUID, TabPlacement) -> Void
    let extensionIcons: [String: NSImage]
    let setExtensionIncluded: ((String, Bool) -> Void)?
    let title: String?

    var body: some View {
        VStack(spacing: 0) {
            BrowserSourceImportChrome(application: application, title: title)

            if !review.extensions.isEmpty {
                BrowserImportSidebarExtensionStrip(
                    extensions: review.extensions,
                    icons: extensionIcons,
                    includedIDs: review.includedExtensionIDs,
                    setIncluded: setExtensionIncluded
                )
                .padding(.horizontal, 10)
                .padding(.top, 7)
            }

            if !sections.pinnedTabs.isEmpty {
                BrowserSourceImportSectionHeader(
                    title: pinnedTitle,
                    tabs: sections.pinnedTabs,
                    includedTabIDs: review.includedTabIDs,
                    setIncluded: setSectionIncluded
                )
                .padding(.horizontal, 13)
                .padding(.top, 8)
                BrowserSourceImportPinnedGrid(
                    review: review,
                    tabs: sections.pinnedTabs,
                    overflowTabIDs: overflowTabIDs,
                    duplicateTabIDs: duplicateTabIDs,
                    duplicateDestinationName: duplicateDestinationName,
                    setIncluded: setIncluded
                )
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 7)
            }

            BrowserSourceImportSpaceHeader(
                application: application,
                title: title,
                space: review.sourceSpace
            )

            if application?.listsNewTab == true, sections.currentTabs.isEmpty {
                Label("New Tab", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    BrowserSourceImportSavedTabs(
                        title: savedTitle,
                        review: review,
                        sections: sections,
                        overflowTabIDs: overflowTabIDs,
                        duplicateTabIDs: duplicateTabIDs,
                        duplicateDestinationName: duplicateDestinationName,
                        setIncluded: setIncluded,
                        setSectionIncluded: setSectionIncluded,
                        setPlacement: setPlacement
                    )

                    if !sections.savedTabs.isEmpty,
                        !sections.currentTabs.isEmpty
                    {
                        Divider()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                    }

                    if !sections.currentTabs.isEmpty {
                        BrowserSourceImportSectionHeader(
                            title: "OPEN TABS",
                            tabs: sections.currentTabs,
                            includedTabIDs: review.includedTabIDs,
                            setIncluded: setSectionIncluded
                        )
                        .padding(.horizontal, 13)
                        ForEach(sections.currentTabs) { tab in
                            BrowserSourceImportTabRow(
                                review: review,
                                tab: tab,
                                overflowTabIDs: overflowTabIDs,
                                duplicateTabIDs: duplicateTabIDs,
                                duplicateDestinationName: duplicateDestinationName,
                                setIncluded: setIncluded,
                                setPlacement: setPlacement
                            )
                        }
                    }
                }
            }

            BrowserSourceImportFooter()
        }
    }

    private var pinnedTitle: LocalizedStringResource {
        application?.pinnedSectionTitle ?? "PINNED"
    }

    private var savedTitle: LocalizedStringResource {
        application?.savedSectionTitle ?? "SAVED"
    }
}
