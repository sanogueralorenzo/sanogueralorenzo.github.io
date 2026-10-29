import Foundation

extension EngineCommand {
    /// Runs the command on the WebKit binding, as the command's own
    /// `perform(on:)` says.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        switch self {
        case .adoptOfferedPage(let command): command.perform(on: binding)
        case .closePage(let command): command.perform(on: binding)
        case .createPage(let command): command.perform(on: binding)
        case .dropStagedLink(let command): command.perform(on: binding)
        case .exitPictureInPicture(let command): command.perform(on: binding)
        case .goToHistoryEntry(let command): command.perform(on: binding)
        case .groupPages:
            // WebKit reports no tab groups, so the core never asks it for one.
            break
        case .loadPage(let command): command.perform(on: binding)
        case .recoverPage(let command): command.perform(on: binding)
        case .rejectOfferedPage(let command): command.perform(on: binding)
        case .stageNavigation(let command): command.perform(on: binding)
        }
    }
}
