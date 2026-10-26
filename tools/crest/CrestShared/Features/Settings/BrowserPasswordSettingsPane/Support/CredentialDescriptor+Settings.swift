import Foundation

/// What settings says about a Space's saved passwords: the search predicate,
/// the manager's order and the delete confirmation both shells used to write
/// their own drifting copy of. None of it needs a Keychain.
extension CredentialDescriptor {
    // MARK: - Actions - Settings

    /// Whether this password matches a trimmed, non-empty settings query over
    /// the four fields both shells searched: the account, the site, the label a
    /// reader gave it, and the authentication scope that narrows it.
    func matches(settingsQuery query: String) -> Bool {
        username.localizedCaseInsensitiveContains(query)
            || origin.description.localizedCaseInsensitiveContains(query)
            || displayName?.localizedCaseInsensitiveContains(query) == true
            || scope.settingsLabel?.localizedCaseInsensitiveContains(query) == true
    }

    /// Everything a reader needs before deleting: whose password, for which site,
    /// under which authentication scope, out of which Space — and whether the delete
    /// reaches past this device.
    func deletionMessage(spaceName: String) -> String {
        let synchronizationWarning =
            isSynchronizable
            ? " This also removes synchronized copies from Crest’s iCloud Keychain item."
            : ""
        let scopeLabel = scope.settingsLabel.map { " (\($0))" } ?? ""
        return
            "Delete \(username)’s password for \(origin.description)\(scopeLabel) from \(spaceName)?\(synchronizationWarning) This cannot be undone."
    }

    /// Whether this password comes before `other` in the manager: by site, then
    /// account, then identity.
    func precedesInSettings(_ other: CredentialDescriptor) -> Bool {
        let siteOrder = origin.host.localizedStandardCompare(other.origin.host)
        if siteOrder != .orderedSame {
            return siteOrder == .orderedAscending
        }
        let usernameOrder = username.localizedStandardCompare(other.username)
        if usernameOrder != .orderedSame {
            return usernameOrder == .orderedAscending
        }
        return id.uuidString < other.id.uuidString
    }
}

extension [CredentialDescriptor] {
    // MARK: - Actions - Settings

    /// The passwords a settings query finds, in the manager's order. A blank
    /// query keeps every one.
    func matching(_ query: String) -> [CredentialDescriptor] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? self : filter { $0.matches(settingsQuery: query) }
        return matches.sorted { $0.precedesInSettings($1) }
    }
}
