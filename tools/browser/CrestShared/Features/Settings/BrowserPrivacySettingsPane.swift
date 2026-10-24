import SwiftUI

/// What a Space blocks, and what it has already been told about individual sites.
struct BrowserPrivacySettingsPane: View {
    let browser: BrowserStore
    let downloadCenter: BrowserDownloadCenter
    let spaceAccess: BrowserSpaceAccessController
    let permissionCenter: BrowserSitePermissionCenter
    let contentBlockingErrorDescription: String?
    /// The one Space whose privacy the pane shows, with its lock, or nil to
    /// pick one.
    var fixedSpaceID: UUID? = nil

    @State private var pickedSpaceID: UUID?
    private var selectedSpaceID: UUID? { fixedSpaceID ?? pickedSpaceID }
    private var selectedSpaceBinding: Binding<UUID?> {
        Binding(get: { selectedSpaceID }, set: { if fixedSpaceID == nil { pickedSpaceID = $0 } })
    }
    @State private var confirmsReset = false

    var body: some View {
        BrowserSettingsPane(.privacy) {
            if fixedSpaceID == nil {
                BrowserPrivacySpaceSection(
                    selectedSpaceID: selectedSpaceBinding,
                    spaces: browser.spaceModels
                )
            }

            if canRevealSelectedSpaceData {
                if fixedSpaceID != nil, let selectedSpace {
                    BrowserSpaceAccessPolicySection(browser: browser, space: selectedSpace, spaceAccess: spaceAccess)
                }

                if let selectedSpaceID {
                    BrowserDataRetentionSettingsSection(
                        browser: browser,
                        downloadCenter: downloadCenter,
                        spaceID: selectedSpaceID
                    )
                }

                // Where blocking comes only from extensions, a toggle could reach
                // no page, so the section is left out.
                if supportsContentBlocking {
                    BrowserContentBlockingSettingsSection(
                        policy: contentBlockingPolicyBinding,
                        errorDescription: contentBlockingErrorDescription
                    )
                }

                if browser.core.state.offers(.permissions) {
                    BrowserSavedSitePermissionSection(
                        records: records,
                        permissionCenter: permissionCenter,
                        resetAll: { confirmsReset = true }
                    )
                }
            } else if let selectedSpace {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: selectedSpace,
                    accessController: spaceAccess,
                    detail: "Unlock this Space to see its privacy settings."
                )
            }
        }
        .crestRepairsSpaceSelection(selectedSpaceBinding, in: browser)
        .onChange(of: canRevealSelectedSpaceData) { _, canReveal in
            if !canReveal {
                confirmsReset = false
            }
        }
        .confirmationDialog(
            "Reset All",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive, action: resetAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Makes every site ask again in this Space")
        }
    }

    private var records: [SitePermissionRecordState] {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return [] }
        return permissionCenter.records(in: selectedSpaceID)
    }

    private var selectedSpace: SpaceModel? {
        guard let selectedSpaceID else { return nil }
        return browser.spaceModel(selectedSpaceID)
    }

    private var canRevealSelectedSpaceData: Bool {
        guard let selectedSpace else { return false }
        return !spaceAccess.isLocked(selectedSpace)
    }

    /// Crest's own blocking is a WebKit content-rule list. An engine either
    /// applies it or it does not, and a preference that cannot reach any page
    /// is worse than an absent one.
    private var supportsContentBlocking: Bool {
        browser.core.state.offers(.contentBlocking)
    }

    private var contentBlockingPolicyBinding: Binding<ContentBlockingPolicy> {
        browser.browsingPreferenceBinding(
            \.contentBlocking,
            in: selectedSpaceID,
            default: .balanced
        )
    }

    private func resetAll() {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return }
        permissionCenter.reset(spaceID: selectedSpaceID)
    }
}
