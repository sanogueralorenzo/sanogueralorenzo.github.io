import SwiftUI

/// The Space-scoped credential work both shells were doing twice.
///
/// Reading a Space's Keychain descriptors, deleting one, turning iCloud
/// synchronization on, and authenticating an export are four operations with four
/// loading flags and five error sentences, and all of it had been written out once in
/// ``BrowserPasswordSettingsPane``'s ancestors on each platform. The sentences differ
/// only where the platform differs — nowhere, as it turned out, which is why the
/// copies had already drifted into "removes synchronized copies *from*" against
/// "*of*" Crest's Keychain item.
@Observable
@MainActor
final class BrowserCredentialSpaceStore {
    private(set) var descriptors: [CredentialDescriptor] = []
    /// How many of the Space's saved passwords no longer read back, which
    /// `descriptors` leaves out.
    private(set) var unreadableCount = 0
    private(set) var isLoading = false
    private(set) var isChangingSynchronization = false
    private(set) var isPreparingExport = false
    private(set) var isPreparingImport = false
    private(set) var isCommittingImport = false
    private(set) var isDeletingSelection = false
    /// Which rows are mid-delete, so a row can show its own progress rather than
    /// blanking the whole list.
    private(set) var deletingCredentialIDs: Set<UUID> = []
    var errorMessage: String?
    var exportDocument: BrowserCredentialCSVDocument?
    var exportFilename = "Crest Passwords.csv"
    var importReview: BrowserCredentialImportReview?
    var importSummary: BrowserCredentialImportSummary?

    @ObservationIgnored private let browser: BrowserStore

    init(browser: BrowserStore) {
        self.browser = browser
    }

    /// The descriptors that match a query, over the four fields both shells searched.
    func descriptors(matching query: String) -> [CredentialDescriptor] {
        descriptors.matching(query)
    }

    func isDeleting(_ descriptor: CredentialDescriptor) -> Bool {
        deletingCredentialIDs.contains(descriptor.id)
    }

    func load(
        in spaceID: UUID?,
        accessController: BrowserSpaceAccessController
    ) async {
        guard let spaceID,
            unlockedSpace(spaceID, accessController: accessController) != nil
        else {
            clearSensitiveData()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loadedDescriptors = try await browser.savedCredentialDescriptors(in: spaceID)
            let loadedUnreadableCount = try await browser.unreadableCredentialCount(in: spaceID)
            guard !Task.isCancelled,
                unlockedSpace(spaceID, accessController: accessController) != nil
            else {
                clearSensitiveData()
                return
            }
            descriptors = loadedDescriptors
            unreadableCount = loadedUnreadableCount
        } catch {
            guard !Task.isCancelled,
                unlockedSpace(spaceID, accessController: accessController) != nil
            else {
                clearSensitiveData()
                return
            }
            descriptors = []
            unreadableCount = 0
            errorMessage = "Crest couldn’t read this Space’s saved-password metadata."
        }
    }

    func clearSensitiveData() {
        descriptors = []
        unreadableCount = 0
        deletingCredentialIDs = []
        errorMessage = nil
        exportDocument = nil
        importReview = nil
        importSummary = nil
    }

    func delete(
        _ descriptor: CredentialDescriptor,
        reloading spaceID: UUID?,
        accessController: BrowserSpaceAccessController
    ) {
        guard unlockedSpace(descriptor.spaceID, accessController: accessController) != nil else { return }
        deletingCredentialIDs.insert(descriptor.id)
        errorMessage = nil
        Task { @MainActor in
            defer { deletingCredentialIDs.remove(descriptor.id) }
            do {
                try await browser.deleteCredential(
                    id: descriptor.id,
                    in: descriptor.spaceID
                )
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = "Crest couldn’t delete that password from this Space."
            }
        }
    }

    /// Removes the Space's saved passwords that no longer read back, which no
    /// list shows and no page is offered.
    func deleteUnreadable(
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController
    ) {
        guard unlockedSpace(spaceID, accessController: accessController) != nil else { return }
        errorMessage = nil
        Task { @MainActor in
            do {
                try await browser.deleteUnreadableCredentials(in: spaceID)
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = String(localized: "Crest couldn’t remove the passwords it can’t read.")
            }
        }
    }

    /// Turning synchronization on or off rewrites the Space's existing Keychain
    /// items, so it is an operation with a progress state and a failure — which is
    /// why it is here rather than among the plain preference bindings.
    func setSynchronization(
        _ enabled: Bool,
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController
    ) {
        guard unlockedSpace(spaceID, accessController: accessController) != nil else { return }
        isChangingSynchronization = true
        errorMessage = nil
        Task { @MainActor in
            defer { isChangingSynchronization = false }
            do {
                try await browser.setCrestPasswordSynchronization(enabled, in: spaceID)
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = "Crest couldn’t update iCloud synchronization."
            }
        }
    }

    func synchronizationBinding(
        in space: SpaceModel,
        accessController: BrowserSpaceAccessController
    ) -> Binding<Bool> {
        Binding {
            space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
        } set: { [weak self] enabled in
            self?.setSynchronization(
                enabled,
                in: space.id,
                accessController: accessController
            )
        }
    }

    /// Authenticates, builds the CSV, and reports whether the exporter should open.
    /// The Space is re-checked afterwards because authentication can outlive the
    /// reader's interest in that Space.
    func prepareExport(
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async -> Bool {
        guard unlockedSpace(spaceID, accessController: accessController) != nil else { return false }
        isPreparingExport = true
        errorMessage = nil
        defer { isPreparingExport = false }
        do {
            let export = try await BrowserCredentialSensitiveAccess(browser: browser)
                .exportCredentials(in: spaceID)
            guard isStillSelected(),
                unlockedSpace(spaceID, accessController: accessController) != nil
            else { return false }
            exportDocument = BrowserCredentialCSVDocument(data: export.contents)
            exportFilename = export.fileName
            return true
        } catch {
            errorMessage = "Crest couldn’t authenticate and export this Space’s passwords."
            return false
        }
    }

    func reportExportFailure() {
        errorMessage = "Crest couldn’t export those passwords."
    }

    func prepareImport(
        from url: URL,
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async {
        guard let space = unlockedSpace(spaceID, accessController: accessController),
            space.settings.credentialPreferences.isEnabled
        else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        isPreparingImport = true
        errorMessage = nil
        importReview = nil
        defer { isPreparingImport = false }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let existing = try await BrowserCredentialSensitiveAccess(browser: browser)
                .credentialInventory(
                    matching: assignment,
                    reason: String(
                        localized: "Authenticate to import passwords into \(space.settings.name)."
                    )
                )
            guard isStillSelected(), browser.spaceModel(matching: assignment) != nil else {
                throw BrowserCredentialSensitiveAccessError.missingCredential
            }
            let plan = try await Self.plan(
                importing: try Self.document(at: url), against: existing, core: browser.core)
            guard isStillSelected(),
                let currentSpace = browser.spaceModel(matching: assignment)
            else {
                throw BrowserCredentialSensitiveAccessError.missingCredential
            }
            importReview = BrowserCredentialImportReview(
                plan: plan,
                existingCredentials: existing,
                destination: assignment,
                synchronizesWithICloud: currentSpace.settings.credentialPreferences.syncsCrestPasswordsWithICloud
            )
        } catch let rejection as Rejection {
            if case .invalidCredentialFile(let invalid) = rejection {
                errorMessage = String(localized: invalid.flaw.message)
            } else {
                errorMessage = rejection.explanation
            }
        } catch {
            errorMessage =
                "Crest couldn’t authenticate and read that password file for this Space."
        }
    }

    /// The file at `url`, read no further than one byte past the largest
    /// password file the core imports, so a larger one is refused as such
    /// without reading it whole.
    private static func document(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: CapacityLimits.current.credentialFileBytes + 1) ?? Data()
    }

    /// The core's plan for importing `document` against `existing`, read away
    /// from the main thread.
    private static func plan(
        importing document: Data,
        against existing: [BrowserCredential],
        core: CrestCore
    ) async throws -> CredentialImportPlan {
        let query = CredentialImportPreview(document: document, existing: existing.map(ExistingCredential.init))
        return try await Task.detached(priority: .userInitiated) { try core.query(query) }.value
    }

    func selectImport(
        _ selection: BrowserCredentialImportSelection,
        for id: BrowserCredentialImportGroupID
    ) {
        importReview?.select(selection, for: id)
    }

    func cancelImport() {
        importReview = nil
    }

    func commitImport(
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async {
        guard let plan = importReview,
            let space = browser.spaceModel(matching: plan.destination),
            !accessController.isLocked(space),
            isStillSelected()
        else { return }
        isCommittingImport = true
        errorMessage = nil
        defer { isCommittingImport = false }
        do {
            let currentInventory = try await BrowserCredentialSensitiveAccess(browser: browser)
                .credentialInventory(
                    matching: plan.destination,
                    reason: String(
                        localized: "Authenticate to commit the password import into \(space.settings.name)."
                    )
                )
            guard plan.matchesExistingInventory(currentInventory) else {
                errorMessage =
                    "This Space’s saved passwords changed during review. No passwords were imported; choose the file again to refresh conflicts."
                importReview = nil
                return
            }
            let resolution = try plan.resolvedInventory()
            guard isStillSelected(), browser.spaceModel(matching: plan.destination) != nil else {
                throw BrowserCredentialSensitiveAccessError.missingCredential
            }
            if resolution.summary.acceptedCount > 0 {
                try await browser.replaceCredentialInventory(
                    resolution.credentials,
                    in: plan.destination.spaceID
                )
            }
            guard isStillSelected(), browser.spaceModel(matching: plan.destination) != nil else {
                throw BrowserCredentialSensitiveAccessError.missingCredential
            }
            importSummary = resolution.summary
            importReview = nil
            await load(
                in: plan.destination.spaceID,
                accessController: accessController
            )
        } catch CredentialVaultError.atomicReplacementRestoreFailed {
            errorMessage =
                "Crest couldn’t finish the import or restore the original Keychain inventory. Review this Space before trying again."
        } catch {
            errorMessage =
                "Crest couldn’t commit the import. The original passwords were restored and no imported passwords were accepted."
        }
    }

    func deleteSelection(
        _ ids: Set<UUID>,
        in spaceID: UUID,
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async -> Bool {
        guard !ids.isEmpty,
            let space = unlockedSpace(spaceID, accessController: accessController)
        else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        isDeletingSelection = true
        errorMessage = nil
        defer { isDeletingSelection = false }
        do {
            let existing = try await BrowserCredentialSensitiveAccess(browser: browser)
                .credentialInventory(
                    matching: assignment,
                    reason: String(
                        localized: "Authenticate to delete selected passwords from \(space.settings.name)."
                    )
                )
            guard isStillSelected(), browser.spaceModel(matching: assignment) != nil else {
                throw BrowserCredentialSensitiveAccessError.missingCredential
            }
            let remaining = existing.filter { !ids.contains($0.descriptor.id) }
            try await browser.replaceCredentialInventory(remaining, in: spaceID)
            await load(in: spaceID, accessController: accessController)
            return true
        } catch CredentialVaultError.atomicReplacementRestoreFailed {
            errorMessage =
                "Crest couldn’t restore the original Keychain inventory after deletion failed. Review this Space before trying again."
            return false
        } catch {
            errorMessage =
                "Crest couldn’t delete the selected passwords. The original passwords were restored."
            return false
        }
    }

    func deletionMessage(
        for descriptor: CredentialDescriptor,
        in space: SpaceModel?
    ) -> String {
        descriptor.deletionMessage(
            spaceName: space?.settings.name
                ?? browser.spaceModel(descriptor.spaceID)?.settings.name
                ?? "this Space"
        )
    }

    /// The Space of the read model the store may reveal and change, while
    /// this process holds it unlocked.
    private func unlockedSpace(
        _ spaceID: UUID,
        accessController: BrowserSpaceAccessController
    ) -> SpaceModel? {
        guard let space = browser.spaceModel(spaceID), !accessController.isLocked(space) else { return nil }
        return space
    }
}
