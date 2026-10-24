import Foundation

/// One step of saving a password, with what the prompt shows and offers there.
/// A step that carries a save or its outcome is made by its factory.
struct BrowserCredentialPromptState: Hashable, Sendable {
    // MARK: - Variables

    static let preparing = BrowserCredentialPromptState(
        name: "preparing", title: { _ in "Checking password…" }, busyActivity: .checkingSavedPasswords)
    static let create = BrowserCredentialPromptState(
        name: "create", title: { _ in BrowserCredentialSavePromptAction.create.promptTitle },
        primaryAction: .commit(.create))
    static let update = BrowserCredentialPromptState(
        name: "update", title: { _ in BrowserCredentialSavePromptAction.update.promptTitle },
        primaryAction: .commit(.update))
    static let alreadyStored = BrowserCredentialPromptState(
        name: "alreadyStored", title: { _ in BrowserCredentialSavePromptAction.create.promptTitle })
    static let failedPreparation = BrowserCredentialPromptState(
        name: "failedPreparation", title: { _ in "Couldn’t check password" },
        primaryAction: .retryCredentialPreparation,
        errorMessage: { _ in "Crest couldn’t check this Space’s saved passwords." })
    static let offeringToSystemPasswords = BrowserCredentialPromptState(
        name: "offeringToSystemPasswords", title: { Self.savedTitle(spaceName: $0) }, dismissAction: .done,
        busyActivity: .openingSystemPasswords)
    static let completedSystemPasswords = BrowserCredentialPromptState(
        name: "completedSystemPasswords", title: { Self.savedTitle(spaceName: $0) }, dismissAction: .done)
    static let failedSystemPasswords = BrowserCredentialPromptState(
        name: "failedSystemPasswords", title: { Self.savedTitle(spaceName: $0) }, primaryAction: .retrySystemPasswords,
        dismissAction: .done,
        errorMessage: { spaceName in
            spaceName.map { "Saved in \($0). The Passwords offer wasn’t completed." }
                ?? "Saved in this Space. The Passwords offer wasn’t completed."
        })

    /// Identifies the step, with the save or outcome it carries.
    let name: String

    let title: @Sendable (_ spaceName: String?) -> LocalizedStringResource
    let primaryAction: BrowserCredentialPromptPrimaryAction?
    let dismissAction: BrowserCredentialPromptDismissAction
    let busyActivity: BrowserCredentialPromptBusyActivity?
    let errorMessage: @Sendable (_ spaceName: String?) -> LocalizedStringResource?

    // MARK: - Initializers

    private init(
        name: String,
        title: @escaping @Sendable (String?) -> LocalizedStringResource,
        primaryAction: BrowserCredentialPromptPrimaryAction? = nil,
        dismissAction: BrowserCredentialPromptDismissAction = .notNow,
        busyActivity: BrowserCredentialPromptBusyActivity? = nil,
        errorMessage: @escaping @Sendable (String?) -> LocalizedStringResource? = { _ in nil }
    ) {
        self.name = name
        self.title = title
        self.primaryAction = primaryAction
        self.dismissAction = dismissAction
        self.busyActivity = busyActivity
        self.errorMessage = errorMessage
    }

    /// The save is running.
    static func saving(_ action: BrowserCredentialSavePromptAction) -> BrowserCredentialPromptState {
        BrowserCredentialPromptState(
            name: "saving \(action.name)", title: { _ in action.promptTitle }, busyActivity: .savingPassword)
    }

    /// The password is saved in the Space.
    static func saved(_ disposition: BrowserCredentialSaveDisposition) -> BrowserCredentialPromptState {
        BrowserCredentialPromptState(
            name: "saved \(disposition)", title: { Self.savedTitle(spaceName: $0) }, dismissAction: .done)
    }

    /// The save failed; trying again checks the Space's passwords first.
    static func failedCommit(_ action: BrowserCredentialSavePromptAction) -> BrowserCredentialPromptState {
        BrowserCredentialPromptState(
            name: "failedCommit \(action.name)", title: { _ in action.promptTitle },
            primaryAction: .retryCredentialPreparation,
            errorMessage: { spaceName in
                spaceName.map { "Crest couldn’t save this password to the \($0) Space." }
                    ?? "Crest couldn’t save this password to this Space."
            })
    }

    // MARK: - Actions - Presentation

    private static func savedTitle(spaceName: String?) -> LocalizedStringResource {
        spaceName.map { "Saved in \($0)" } ?? "Saved in this Space"
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCredentialPromptState, rhs: BrowserCredentialPromptState) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
