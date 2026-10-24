import Foundation
import Observation

/// Prepares a quit through the core, for either engine's composition: the core
/// asks every page whether it may go, then asks the person whether to stop the
/// downloads still in progress, which this shows as an alert on the key window.
///
/// While the engines erase a Space being deleted the core defers the quit.
/// This tells the person Crest will quit once the Space is deleted, and asks
/// the entry point to quit again whenever a deletion this device runs ends,
/// finished or failed, until the core allows it.
@MainActor
final class BrowserQuitPreparation {
    // MARK: - Variables

    private weak var core: CrestCore?
    private let dialogs = BrowserDialogPresenter()
    /// How to close the question about downloads in progress, while it waits.
    private var dismissals: [UUID: BrowserPromptDismissal] = [:]
    /// The Space deletions this device is running now, which a deferred quit
    /// watches. A deletion that failed stays pending in the core, so the
    /// running ones are what change when an attempt ends.
    private let deletingSpaces: @MainActor () -> Set<UUID>
    /// The deferred quit whose wait is current; an older one's is dropped.
    private var waiting: UUID?
    /// A quit waits for a Space's deletion, and the person was told.
    private var isDeferred = false

    // MARK: - Initializers

    init(core: CrestCore, deletingSpaces: @escaping @MainActor () -> Set<UUID>) {
        self.core = core
        self.deletingSpaces = deletingSpaces
        core.followPrompts(self)
    }

    // MARK: - Actions - Quitting

    /// Asks the core whether the app may quit, and calls `completion` with the
    /// answer on a later turn of the main actor. A quit the core defers while
    /// a Space is being deleted answers false, and `retry` runs once the
    /// deletion moved on, so the entry point asks to quit again.
    func prepare(retry: @escaping @MainActor () -> Void, completion: @escaping @MainActor (Bool) -> Void) {
        guard let core else {
            Task { @MainActor in completion(false) }
            return
        }
        core.prepareToClose(
            PrepareToQuit(requestID: UUID()),
            refused: { [weak self] rejection in
                if case .spaceDeletionUnderway(let underway) = rejection {
                    self?.waitForSpaceDeletions(underway, retry: retry)
                } else {
                    self?.settle()
                }
                Task { @MainActor in completion(false) }
            },
            completion: { [weak self] allowed in
                self?.settle()
                Task { @MainActor in completion(allowed) }
            })
    }

    /// The quit ended, allowed or refused for a reason no deletion settles.
    private func settle() {
        waiting = nil
        isDeferred = false
    }

    // MARK: - Actions - Space deletion

    /// Tells the person, once per quit, that Crest quits when the Space is
    /// deleted, and calls `retry` once the deletions this device is running
    /// change.
    private func waitForSpaceDeletions(_ underway: SpaceDeletionUnderway, retry: @escaping @MainActor () -> Void) {
        if !isDeferred {
            isDeferred = true
            BrowserNoticeCenter.shared.post(
                BrowserNotice(message: String(localized: underway.message), systemImage: "trash"))
        }
        let wait = UUID()
        waiting = wait
        watchSpaceDeletions(since: deletingSpaces(), wait: wait, retry: retry)
    }

    /// Calls `retry` for the deferred quit `wait` once the running deletions
    /// differ from `deleting`, watching them until then.
    private func watchSpaceDeletions(since deleting: Set<UUID>, wait: UUID, retry: @escaping @MainActor () -> Void) {
        guard waiting == wait else { return }
        let now = withObservationTracking {
            deletingSpaces()
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchSpaceDeletions(since: deleting, wait: wait, retry: retry) }
        }
        guard now != deleting else { return }
        waiting = nil
        retry()
    }
}

/// Shows the question about downloads in progress, and closes it once the
/// core settles it.
extension BrowserQuitPreparation: CorePromptHost {
    /// The engine hosting the page shows its dialogs.
    func ask(_ asked: ScriptDialogAsked) {}

    /// The engine hosting the page shows its sign-in.
    func ask(_ asked: AuthenticationAsked) {}

    /// The engine hosting the page shows its permission request.
    func ask(_ asked: PermissionAsked) {}

    /// The Chromium engine reviews extension installs.
    func ask(_ asked: ExtensionInstallAsked) {}

    /// The download prompts choose where a download goes.
    func ask(_ asked: DownloadDestinationAsked) {}

    /// The download prompts ask whether a download may go ahead.
    func ask(_ asked: DownloadApprovalAsked) {}

    func ask(_ asked: QuitWithDownloadsAsked) {
        let dismissal = BrowserPromptDismissal()
        dismissals[asked.promptID] = dismissal
        Task { @MainActor [weak self] in
            guard let self else { return }
            let quits = await dialogs.approveQuitWithDownloads(count: asked.liveDownloads, dismissal: dismissal)
            _ = try? core?.send(AnswerQuitWithDownloads(promptID: asked.promptID, quits: quits))
        }
    }

    func dismiss(_ settled: PromptSettled) {
        dismissals.removeValue(forKey: settled.promptID)?.dismiss()
    }
}
