import Foundation

extension EngineCommand {
    /// Notes in `hosts` the page this command gives the engine `kind` or takes
    /// from it, as the command's own `note(runningOn:in:)` says.
    func note(runningOn kind: EngineKind, in hosts: inout [UUID: EngineKind]) {
        switch self {
        case .adoptOfferedPage(let command): command.note(runningOn: kind, in: &hosts)
        case .closePage(let command): command.note(runningOn: kind, in: &hosts)
        case .createPage(let command): command.note(runningOn: kind, in: &hosts)
        case .approveEngineDownload, .cancelEngineDownload, .checkBeforeUnload, .dropStagedLink, .eraseProfileData,
            .eraseSiteData, .exitPictureInPicture, .goToHistoryEntry, .groupPages, .loadPage, .pauseEngineDownload,
            .recoverPage, .rejectOfferedPage, .removeEngineDownload, .resumeEngineDownload, .settleAuthentication,
            .settleDownloadDestination, .settleExtensionInstall, .settlePermission, .settleScriptDialog,
            .stageNavigation:
            // These act on a page the engine already hosts, or on none.
            break
        }
    }
}
