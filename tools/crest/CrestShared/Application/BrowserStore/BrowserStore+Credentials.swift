import Foundation

// MARK: - Suggestion Loading

extension BrowserStore: BrowserCredentialSuggestionLoading {
    func credentialSuggestions(
        for origin: CredentialOrigin,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        guard let url = URL(string: origin.description) else {
            throw CredentialVaultError.invalidOrigin
        }
        return try await credentialSuggestions(for: url, in: spaceID)
    }
}

// MARK: - Lookup

extension BrowserStore {
    func credentialSuggestions(for url: URL) async throws -> [CredentialDescriptor] {
        guard let spaceID = shownSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialSuggestions(for: url, in: spaceID)
    }

    func savedCredentialDescriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialVault.descriptors(in: spaceID)
    }

    /// How many saved passwords in the Space no longer read back, which every
    /// list and suggestion leaves out.
    func unreadableCredentialCount(in spaceID: UUID) async throws -> Int {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialVault.unreadableCredentialCount(in: spaceID)
    }

    func credentialSuggestions(
        for url: URL,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        guard let space = spaceModel(spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.settings.credentialPreferences.isEnabled else { return [] }
        guard let origin = CredentialOrigin(url: url) else {
            throw CredentialVaultError.invalidOrigin
        }
        guard origin.isSecure else { return [] }
        return try await credentialVault.descriptors(matching: origin, in: spaceID)
    }

    func credential(id: UUID) async throws -> BrowserCredential? {
        guard let spaceID = shownSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await credential(id: id, in: spaceID)
    }

    func credential(id: UUID, in spaceID: UUID) async throws -> BrowserCredential? {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        return try await credentialVault.credential(id: id, in: spaceID)
    }

    func credentialInventory(in spaceID: UUID) async throws -> [BrowserCredential] {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        let descriptors = try await credentialVault.descriptors(in: spaceID)
        var credentials: [BrowserCredential] = []
        credentials.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            guard
                let credential = try await credentialVault.credential(
                    id: descriptor.id,
                    in: spaceID
                ),
                credential.descriptor == descriptor,
                credential.descriptor.spaceID == spaceID
            else {
                throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
            }
            credentials.append(credential)
        }
        return credentials
    }

    func httpAuthenticationCredential(
        for protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> BrowserCredential? {
        guard let space = spaceModel(spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.settings.credentialPreferences.isEnabled else { return nil }
        guard protectionSpace.origin.isSecure else { return nil }
        let descriptors = try await credentialVault.descriptors(
            matching: protectionSpace,
            in: spaceID
        )
        // Without a recency answer from the core, nothing is filled.
        guard let descriptor = try? core.mostRecentCredential(descriptors) else {
            return nil
        }
        return try await credentialVault.credential(id: descriptor.id, in: spaceID)
    }
}

// MARK: - Generated passwords and system Passwords

extension BrowserStore {
    /// How to compose a generated password. The password itself is drawn
    /// natively, so it never enters the core.
    func strongPasswordRecipe() throws -> StrongPasswordRecipe {
        do {
            return try core.query(StrongPassword(length: nil))
        } catch {
            throw BrowserStrongPasswordGenerationError.unavailable
        }
    }

    /// Whether this launch can offer saved passwords to the system's Passwords
    /// app. A core that refuses the platform's facts reports it unsupported.
    var systemPasswordWriteThroughAvailability: SystemPasswordWriteThroughAvailability {
        (try? core.query(BrowserSystemPasswordWriteThroughSystem.facts()))?.availability ?? .unsupportedPlatform
    }

    /// Whether a save prompt in a Space with these preferences goes on to
    /// offer the password to the system's Passwords app. A core that cannot
    /// answer does not offer it.
    func offersSystemPasswordWriteThrough(for preferences: CredentialPreferences) -> Bool {
        let offer = SystemPasswordOffer(
            spaceOffersSystemPasswords: preferences.alsoOffersSaveToSystemPasswords,
            availability: systemPasswordWriteThroughAvailability, isPrivateBrowsing: isPrivateBrowsing)
        return (try? core.query(offer))?.offers ?? false
    }
}

// MARK: - Preferences

extension BrowserStore {
    func updateCredentialPreferences(
        _ preferences: CredentialPreferences,
        in spaceID: UUID
    ) {
        sendSpaceSettings(
            SetCredentialPreferences(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID, preferences: preferences))
    }

    func setCrestPasswordSynchronization(
        _ isSynchronizable: Bool,
        in spaceID: UUID
    ) async throws {
        // The vault write and its preference belong to the store that owns
        // the Space's credential settings, which may be a borrowed source.
        let owner = profileSettingsBrowser
        guard owner === self else {
            try await owner.setCrestPasswordSynchronization(isSynchronizable, in: spaceID)
            return
        }
        guard let space = spaceModel(spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard space.settings.credentialPreferences.syncsCrestPasswordsWithICloud != isSynchronizable else {
            return
        }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)

        try await credentialVault.setSynchronizable(isSynchronizable, in: spaceID)
        guard let current = spaceModel(matching: assignment)?.settings.credentialPreferences else {
            throw CredentialVaultError.missingSpace
        }
        let preferences = CredentialPreferences(
            isEnabled: current.isEnabled, syncsCrestPasswordsWithICloud: isSynchronizable,
            alsoOffersSaveToSystemPasswords: current.alsoOffersSaveToSystemPasswords)
        // The native credential operation completed for this profile. Persist
        // its corresponding policy through the same session authority.
        let sent = SetCredentialPreferences(workspaceID: family.workspaceID, spaceID: spaceID, preferences: preferences)
        if !family.send(sent, from: self, failure: "Core Space command failed"),
            spaceModel(spaceID)?.settings.credentialPreferences != preferences
        {
            throw CredentialVaultError.preferenceUpdateFailed
        }
    }

}

// MARK: - Saving

extension BrowserStore {
    /// The core matches the account and plans the save from descriptors
    /// alone. The stored password is compared here and only the answer is
    /// passed on. A core that cannot answer fails the plan: nothing is saved.
    func credentialSavePlan(
        for candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date = .now
    ) async throws -> any BrowserCredentialSavePlan {
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        let descriptors = try await credentialVault.descriptors(
            matching: candidate.origin,
            in: spaceID
        )
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        let descriptor: CredentialDescriptor?
        do {
            descriptor = try core.credentialSaveMatch(username: candidate.username, in: descriptors)
        } catch {
            throw CredentialVaultError.saveDecisionUnavailable
        }
        var storedPasswordMatches: Bool?
        if let descriptor {
            let credential = try await credentialVault.credential(
                id: descriptor.id,
                in: spaceID
            )
            try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
            storedPasswordMatches = credential.map { $0.password == candidate.password }
        }
        let stored = descriptor.flatMap { descriptor in
            storedPasswordMatches.map {
                CredentialStoredComparison(id: descriptor.id, passwordMatches: $0)
            }
        }
        guard let plan = try? core.query(CredentialSave(matchID: descriptor?.id, stored: stored)),
            plan.kind == .create || plan.id == descriptor?.id
        else { throw CredentialVaultError.saveDecisionUnavailable }
        switch (plan.kind, descriptor) {
        case (.create, _): return BrowserCredentialCreatePlan()
        case (.update, let descriptor?): return BrowserCredentialUpdatePlan(existing: descriptor)
        case (.alreadyStored, let descriptor?): return BrowserCredentialAlreadyStoredPlan(existing: descriptor)
        default: throw CredentialVaultError.saveDecisionUnavailable
        }
    }

    func commitCredentialSave(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date = .now
    ) async throws -> BrowserCredentialSaveResult {
        try validateCredentialSaveCandidate(candidate, in: spaceID, now: now)
        let key = BrowserCredentialSaveKey(candidate: candidate, spaceID: spaceID)
        let precedingCompletion = credentialSaveOperations[key]?.completion
        let operationID = UUID()
        let task = Task { @MainActor [self] in
            if let precedingCompletion {
                await precedingCompletion.value
            }
            return try await performCredentialSave(
                candidate,
                in: spaceID,
                now: now
            )
        }
        let completion = Task {
            _ = try? await task.value
        }
        credentialSaveOperations[key] = BrowserCredentialSaveOperation(
            id: operationID,
            completion: completion
        )
        defer {
            if credentialSaveOperations[key]?.id == operationID {
                credentialSaveOperations[key] = nil
            }
        }
        return try await task.value
    }

    @discardableResult
    func saveCredential(
        username: String,
        password: String,
        for url: URL,
        displayName: String? = nil,
        isSynchronizable: Bool? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        guard let spaceID = shownSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        return try await saveCredential(
            username: username,
            password: password,
            for: url,
            in: spaceID,
            displayName: displayName,
            replacing: nil,
            isSynchronizable: isSynchronizable,
            now: now
        )
    }

    @discardableResult
    func saveCredential(
        username: String,
        password: String,
        for url: URL,
        in spaceID: UUID,
        displayName: String? = nil,
        replacing existing: CredentialDescriptor? = nil,
        isSynchronizable: Bool? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        guard let space = spaceModel(spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        guard space.settings.credentialPreferences.isEnabled else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        let resolvedSynchronization =
            isSynchronizable
            ?? space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
        guard let origin = CredentialOrigin(url: url) else {
            throw CredentialVaultError.invalidOrigin
        }
        guard origin.isSecure else {
            throw CredentialVaultError.insecureOrigin
        }

        let descriptor: CredentialDescriptor
        if var existing {
            guard existing.spaceID == spaceID else {
                throw CredentialVaultError.spaceMismatch(
                    expected: spaceID,
                    actual: existing.spaceID
                )
            }
            guard existing.origin == origin else {
                throw CredentialVaultError.invalidOrigin
            }
            existing.username = username
            existing.displayName = displayName?.nilIfEmpty ?? existing.displayName
            existing.updatedAt = now
            existing.isSynchronizable = resolvedSynchronization
            descriptor = existing
        } else {
            descriptor = CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                username: username,
                displayName: displayName?.nilIfEmpty,
                createdAt: now,
                isSynchronizable: resolvedSynchronization
            )
        }
        try await credentialVault.save(
            BrowserCredential(descriptor: descriptor, password: password),
            in: spaceID
        )
        return descriptor
    }

    @discardableResult
    func saveHTTPAuthenticationCredential(
        username: String,
        password: String,
        protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID,
        replacing existing: CredentialDescriptor? = nil,
        now: Date = Date()
    ) async throws -> CredentialDescriptor {
        guard let space = spaceModel(spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        guard space.settings.credentialPreferences.isEnabled else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        guard protectionSpace.origin.isSecure else {
            throw CredentialVaultError.insecureOrigin
        }

        let descriptor: CredentialDescriptor
        if var existing {
            guard existing.spaceID == spaceID else {
                throw CredentialVaultError.spaceMismatch(
                    expected: spaceID,
                    actual: existing.spaceID
                )
            }
            guard existing.origin == protectionSpace.origin,
                existing.scope == protectionSpace.credentialScope
            else {
                throw CredentialVaultError.invalidOrigin
            }
            existing.username = username
            existing.updatedAt = now
            existing.lastUsedAt = now
            existing.isSynchronizable =
                space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
            descriptor = existing
        } else {
            descriptor = CredentialDescriptor(
                spaceID: spaceID,
                origin: protectionSpace.origin,
                scope: protectionSpace.credentialScope,
                username: username,
                createdAt: now,
                lastUsedAt: now,
                isSynchronizable:
                    space.settings.credentialPreferences.syncsCrestPasswordsWithICloud
            )
        }
        try await credentialVault.save(
            BrowserCredential(descriptor: descriptor, password: password),
            in: spaceID
        )
        return descriptor
    }

    func deleteCredential(id: UUID) async throws {
        guard let spaceID = shownSpace?.id else {
            throw CredentialVaultError.missingSpace
        }
        try await deleteCredential(id: id, in: spaceID)
    }

    func deleteCredential(id: UUID, in spaceID: UUID) async throws {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        try await credentialVault.delete(id: id, in: spaceID)
    }

    func deleteUnreadableCredentials(in spaceID: UUID) async throws {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        try await credentialVault.deleteUnreadableCredentials(in: spaceID)
    }

    func replaceCredentialInventory(
        _ credentials: [BrowserCredential],
        in spaceID: UUID
    ) async throws {
        guard spaceModel(spaceID) != nil else {
            throw CredentialVaultError.missingSpace
        }
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        for credential in credentials {
            guard credential.descriptor.spaceID == spaceID else {
                throw CredentialVaultError.spaceMismatch(
                    expected: spaceID,
                    actual: credential.descriptor.spaceID
                )
            }
        }
        try await credentialVault.replaceAll(credentials, in: spaceID)
    }

    private func performCredentialSave(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date
    ) async throws -> BrowserCredentialSaveResult {
        let plan = try await credentialSavePlan(
            for: candidate,
            in: spaceID,
            now: now
        )
        return try await plan.commit(candidate, in: spaceID, now: now, on: self)
    }

    /// Saves `candidate` in the Space `spaceID`, in place of `existing` when
    /// it names the account the candidate changes.
    func saveCredential(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        replacing existing: CredentialDescriptor?,
        now: Date
    ) async throws -> CredentialDescriptor {
        guard let url = URL(string: candidate.origin.description) else {
            throw CredentialVaultError.invalidOrigin
        }
        return try await saveCredential(
            username: candidate.username,
            password: candidate.password,
            for: url,
            in: spaceID,
            replacing: existing,
            now: now
        )
    }

    private func validateCredentialSaveCandidate(
        _ candidate: BrowserCredentialSaveCandidate,
        in spaceID: UUID,
        now: Date
    ) throws {
        guard let space = spaceModel(spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        guard !isPrivateBrowsing else {
            throw CredentialVaultError.unavailableInPrivateBrowsing
        }
        guard space.settings.credentialPreferences.isEnabled else {
            throw CredentialVaultError.credentialManagerDisabled
        }
        let check = CredentialSaveCheck(
            origin: candidate.origin, topLevelOrigin: candidate.topLevelOrigin,
            submittedAt: candidate.submittedAt.timeIntervalSince1970, now: now.timeIntervalSince1970)
        switch (try? core.query(check))?.validity {
        case .accepted: return
        case .insecureOrigin: throw CredentialVaultError.insecureOrigin
        case .stale: throw CredentialVaultError.staleSaveCandidate
        case nil: throw CredentialVaultError.saveDecisionUnavailable
        }
    }
}
