import Foundation

/// The download center one browsing mode shares across every window, the
/// confirmation its risky downloads wait on, and the answers to the core's
/// questions about its Spaces' downloads. The core holds every mode's records;
/// each window shows the records of the profiles it browses.
@MainActor
struct MobileBrowserDownloads {
    // MARK: - Variables

    let center: BrowserDownloadCenter
    let riskConfirmation: MobileDownloadRiskConfirmationCoordinator
    let prompts: BrowserDownloadPrompts

    // MARK: - Initializers

    init(
        core: CrestCore,
        browsingMode: BrowserBrowsingMode = .standard,
        permissionCenter: BrowserSitePermissionCenter
    ) {
        let riskConfirmation = MobileDownloadRiskConfirmationCoordinator()
        self.riskConfirmation = riskConfirmation
        center = BrowserDownloadCenter(
            core: core,
            approveRiskyDownload: { assessment, sourceURL, spaceName, profileID in
                await riskConfirmation.requestApproval(
                    assessment: assessment,
                    sourceURL: sourceURL,
                    spaceName: spaceName,
                    profileID: profileID
                )
            },
            permissionCenter: permissionCenter
        )
        // The mode answers for its own Spaces: private windows' for private
        // browsing, every other one's otherwise.
        let isPrivate = browsingMode.isPrivate
        let space: @MainActor (UUID?) -> SpaceModel? = { [weak core] spaceID in
            guard let spaceID, let core else { return nil }
            return core.state.workspaces.values.lazy.filter { $0.kind.isPrivate == isPrivate }
                .compactMap { $0.spaces.model(spaceID) }.first
        }
        prompts = BrowserDownloadPrompts(
            core: core, claims: { space($0) != nil },
            approve: { [weak core] asked, dismissal in
                guard let owner = space(asked.spaceID),
                    let profileID = core?.state.downloads.first(where: { $0.id == asked.downloadID })?.profileID
                else { return false }
                return await riskConfirmation.requestApproval(
                    for: asked, spaceName: owner.settings.name, profileID: profileID, dismissal: dismissal)
            })
    }
}
