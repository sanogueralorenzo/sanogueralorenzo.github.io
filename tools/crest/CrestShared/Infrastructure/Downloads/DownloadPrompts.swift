import Foundation

/// Answers the questions the core asks about the downloads engines run,
/// whichever engine runs them: where each file goes, and whether to go on
/// with one the core or its engine judged dangerous. One follows each core,
/// or one each browsing mode whose Spaces it claims.
@MainActor
final class BrowserDownloadPrompts {
    // MARK: - Types

    /// Asks the person whether to go on with the download `asked` is about,
    /// until the dismissal closes the question.
    typealias Approve = @MainActor (_ asked: DownloadApprovalAsked, _ dismissal: BrowserPromptDismissal) async -> Bool

    // MARK: - Variables

    private(set) weak var core: CrestCore?
    /// Whether this answers for the Space a question names, or for a
    /// question that names none.
    private let claims: @MainActor (UUID?) -> Bool
    private let approve: Approve
    private let resolveDestination: BrowserDownloadCenter.DownloadDestinationChooser
    /// What closes each approval the person is shown, until the core settles it.
    private var dismissals: [UUID: BrowserPromptDismissal] = [:]
    /// The folder access each download writing into a chosen folder holds
    /// until it ends.
    var downloadFolders: [UUID: URL] = [:]

    // MARK: - Initializers

    /// Answers `core`'s download questions about the Spaces it `claims`,
    /// asking the person with `approve` and choosing each file's place with
    /// `resolveDestination`.
    init(
        core: CrestCore,
        claims: @escaping @MainActor (UUID?) -> Bool = { _ in true },
        approve: @escaping Approve,
        resolveDestination: @escaping BrowserDownloadCenter.DownloadDestinationChooser = {
            await BrowserPlatformDownloadDirectory.resolve(suggestedFilename: $0, spaceID: $1, forcesPrompt: $2)
        }
    ) {
        self.core = core
        self.claims = claims
        self.approve = approve
        self.resolveDestination = resolveDestination
        core.followPrompts(self)
        core.followDownloads(self) { [weak self] download in
            guard !download.phase.isLive else { return }
            self?.downloadFolders.removeValue(forKey: download.id)?.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Actions - Prompts

    /// Where a download's file goes: the Space's download folder, or where
    /// the person chooses when the Space or the engine asks for that.
    private func choose(_ asked: DownloadDestinationAsked) {
        Task { @MainActor [weak self, resolveDestination] in
            let resolution = await resolveDestination(asked.suggestedFilename, asked.spaceID, asked.forcesPrompt)
            guard let self else { return resolution.abandon() }
            resolution.answer(asked, for: self)
        }
    }

    /// Sends the person's answer to a question the core asked. An answer to a
    /// question that no longer waits changes nothing.
    func answer(_ intent: some PromptIntent) {
        _ = try? core?.send(intent)
    }
}

/// Answers a question the core asks about a download, and closes an approval
/// once the core settles it.
extension BrowserDownloadPrompts: CorePromptHost {
    /// The engine hosting the page shows its dialogs.
    func ask(_ asked: ScriptDialogAsked) {}

    /// The engine hosting the page shows its sign-in.
    func ask(_ asked: AuthenticationAsked) {}

    /// The engine hosting the page shows its permission request.
    func ask(_ asked: PermissionAsked) {}

    /// The Chromium engine reviews extension installs.
    func ask(_ asked: ExtensionInstallAsked) {}

    /// The quit preparation asks about downloads in progress.
    func ask(_ asked: QuitWithDownloadsAsked) {}

    func ask(_ asked: DownloadDestinationAsked) {
        guard claims(asked.spaceID) else { return }
        choose(asked)
    }

    func ask(_ asked: DownloadApprovalAsked) {
        guard claims(asked.spaceID) else { return }
        let dismissal = BrowserPromptDismissal()
        dismissals[asked.promptID] = dismissal
        Task { @MainActor [weak self, approve] in
            let approved = await approve(asked, dismissal)
            self?.answer(AnswerDownloadApproval(promptID: asked.promptID, approved: approved))
        }
    }

    func dismiss(_ settled: PromptSettled) {
        dismissals.removeValue(forKey: settled.promptID)?.dismiss()
    }
}
