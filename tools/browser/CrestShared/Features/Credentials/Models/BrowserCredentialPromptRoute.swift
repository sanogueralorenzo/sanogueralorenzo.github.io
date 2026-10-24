import Foundation

/// What the save prompt is busy doing while it cannot be answered.
struct BrowserCredentialPromptBusyActivity: Hashable, Sendable {
    // MARK: - Variables

    static let checkingSavedPasswords = BrowserCredentialPromptBusyActivity(
        name: "checkingSavedPasswords", accessibilityLabel: "Checking saved passwords")
    static let savingPassword = BrowserCredentialPromptBusyActivity(
        name: "savingPassword", accessibilityLabel: "Saving password")
    static let openingSystemPasswords = BrowserCredentialPromptBusyActivity(
        name: "openingSystemPasswords", accessibilityLabel: "Opening Passwords")

    let name: String

    /// What the spinner that stands in for the commit action says.
    let accessibilityLabel: LocalizedStringResource

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialPromptBusyActivity, rhs: BrowserCredentialPromptBusyActivity) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// How the cross-origin warning names the credential it is about.
struct BrowserCredentialPromptCrossOriginSubject: Hashable, Sendable {
    // MARK: - Variables

    static let definiteCredential = BrowserCredentialPromptCrossOriginSubject(
        name: "definiteCredential",
        message: { frame, topLevel in
            "The credential belongs to the embedded \(frame.description) frame, not \(topLevel.description)."
        })
    static let currentCredential = BrowserCredentialPromptCrossOriginSubject(
        name: "currentCredential",
        message: { frame, topLevel in
            "This credential belongs to the embedded \(frame.description) frame, not \(topLevel.description)."
        })

    let name: String

    /// The warning for a credential that belongs to an embedded frame's origin
    /// rather than the page's.
    let message:
        @Sendable (_ frameOrigin: CredentialOrigin, _ topLevelOrigin: CredentialOrigin) -> LocalizedStringResource

    // MARK: - Actions - Identity

    static func == (
        lhs: BrowserCredentialPromptCrossOriginSubject, rhs: BrowserCredentialPromptCrossOriginSubject
    ) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct BrowserCredentialPromptDestinationMetadata: Sendable {
    let detail: LocalizedStringResource
    let syncStatus: LocalizedStringResource?
}

enum BrowserCredentialPromptDestinationPresentation: Equatable, Sendable {
    case combinedStatus
    case separateSyncStatus
}

/// How the prompt is put away.
struct BrowserCredentialPromptDismissAction: Hashable, Sendable {
    // MARK: - Variables

    static let notNow = BrowserCredentialPromptDismissAction(name: "notNow", title: "Not Now")
    static let done = BrowserCredentialPromptDismissAction(name: "done", title: "Done")

    let name: String
    let title: LocalizedStringResource

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialPromptDismissAction, rhs: BrowserCredentialPromptDismissAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// What the prompt's prominent button does, and what it is called.
struct BrowserCredentialPromptPrimaryAction: Hashable, Sendable {
    // MARK: - Variables

    static let retryCredentialPreparation = BrowserCredentialPromptPrimaryAction(
        name: "retryCredentialPreparation", action: nil, title: { _, _ in "Try Again" },
        perform: { performer in performer.retryPreparation() })
    static let retrySystemPasswords = BrowserCredentialPromptPrimaryAction(
        name: "retrySystemPasswords", action: nil, title: { _, _ in "Try Passwords Again" },
        perform: { performer in performer.retrySystemPasswords() })

    let name: String

    /// The save a commit performs.
    let action: BrowserCredentialSavePromptAction?

    /// The button's title for the Space the password is saved in, and whether
    /// the save also offers the password to the system's Passwords app.
    let title: @Sendable (_ spaceName: String?, _ offersSystemPasswords: Bool) -> LocalizedStringResource

    /// Runs the button on the prompt that shows it.
    let perform: @MainActor @Sendable (_ performer: any BrowserCredentialPromptPerformer) -> Void

    // MARK: - Initializers

    /// Saves or updates the password.
    static func commit(_ action: BrowserCredentialSavePromptAction) -> BrowserCredentialPromptPrimaryAction {
        BrowserCredentialPromptPrimaryAction(
            name: "commit", action: action,
            title: { spaceName, offersSystemPasswords in
                offersSystemPasswords ? action.offerTitle : action.commitTitle(spaceName)
            },
            perform: { performer in performer.save() })
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialPromptPrimaryAction, rhs: BrowserCredentialPromptPrimaryAction) -> Bool {
        lhs.name == rhs.name && lhs.action == rhs.action
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(action)
    }
}

/// Maps the credential workflow onto one prompt state, which says what the
/// prompt shows and offers.
struct BrowserCredentialPromptRoute: Equatable, Sendable {
    // MARK: - Variables

    let state: BrowserCredentialPromptState
    let offersSystemPasswords: Bool

    var primaryAction: BrowserCredentialPromptPrimaryAction? {
        state.primaryAction
    }

    var dismissAction: BrowserCredentialPromptDismissAction {
        state.dismissAction
    }

    var busyActivity: BrowserCredentialPromptBusyActivity? {
        state.busyActivity
    }

    var isBusy: Bool {
        busyActivity != nil
    }

    var dismissActionTitle: LocalizedStringResource {
        dismissAction.title
    }

    var busyAccessibilityLabel: LocalizedStringResource? {
        busyActivity?.accessibilityLabel
    }

    // MARK: - Initializers

    init(
        phase: BrowserCredentialSavePromptPhase,
        systemPasswordOfferPhase: BrowserSystemPasswordOfferPhase,
        offersSystemPasswords: Bool
    ) {
        self.offersSystemPasswords = offersSystemPasswords

        guard case .saved = phase else {
            state = Self.state(for: phase)
            return
        }

        state =
            switch systemPasswordOfferPhase {
            case .notRequested:
                Self.state(for: phase)
            case .offering:
                .offeringToSystemPasswords
            case .completed:
                .completedSystemPasswords
            case .failed:
                .failedSystemPasswords
            }
    }

    // MARK: - Actions - Presentation

    func title(spaceName: String?) -> LocalizedStringResource {
        state.title(spaceName)
    }

    func primaryActionTitle(spaceName: String?) -> LocalizedStringResource? {
        primaryAction?.title(spaceName, offersSystemPasswords)
    }

    func errorMessage(spaceName: String?) -> LocalizedStringResource? {
        state.errorMessage(spaceName)
    }

    func crossOriginMessage(
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        subject: BrowserCredentialPromptCrossOriginSubject
    ) -> LocalizedStringResource {
        subject.message(frameOrigin, topLevelOrigin)
    }

    func destinationMetadata(
        spaceName: String?,
        syncsWithICloud: Bool,
        presentation: BrowserCredentialPromptDestinationPresentation
    ) -> BrowserCredentialPromptDestinationMetadata {
        if offersSystemPasswords {
            return BrowserCredentialPromptDestinationMetadata(
                detail: spaceName.map { "Crest saves in \($0) first; Passwords asks separately" }
                    ?? "Crest saves in this Space first; Passwords asks separately",
                syncStatus: nil
            )
        }

        if syncsWithICloud, presentation == .combinedStatus {
            return BrowserCredentialPromptDestinationMetadata(
                detail: spaceName.map { "Stored only in \($0), with Crest iCloud sync" }
                    ?? "Stored only in this Space, with Crest iCloud sync",
                syncStatus: nil
            )
        }

        return BrowserCredentialPromptDestinationMetadata(
            detail: spaceName.map { "Stored only in the \($0) Space" } ?? "Stored only in this Space",
            syncStatus: syncsWithICloud ? "Crest iCloud sync on" : nil
        )
    }

    /// The workflow is a union of phases, so this one place maps each onto
    /// its prompt state.
    private static func state(for phase: BrowserCredentialSavePromptPhase) -> BrowserCredentialPromptState {
        switch phase {
        case .preparing:
            .preparing
        case .create:
            .create
        case .update:
            .update
        case .alreadyStored:
            .alreadyStored
        case .saving(let action):
            .saving(action)
        case .saved(let disposition):
            .saved(disposition)
        case .failed(.preparation):
            .failedPreparation
        case .failed(.commit(let action)):
            .failedCommit(action)
        }
    }
}
