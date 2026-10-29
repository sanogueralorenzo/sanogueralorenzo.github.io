import Foundation

extension EngineCommand {
    /// Track which page identities WebKit currently hosts.
    func note(in hosts: inout Set<UUID>) {
        switch self {
        case .adoptOfferedPage(let command): hosts.insert(command.pageID)
        case .closePage(let command): hosts.remove(command.pageID)
        case .createPage(let command): hosts.insert(command.pageID)
        case .dropStagedLink,
            .exitPictureInPicture, .goToHistoryEntry, .groupPages, .loadPage,
            .recoverPage, .rejectOfferedPage,
            .stageNavigation:
            // These act on a page the engine already hosts, or on none.
            break
        }
    }
}
