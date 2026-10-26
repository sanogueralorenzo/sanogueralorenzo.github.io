import Foundation

/// Credential questions over the vault's descriptors. Only identities, dates
/// and, where accounts are matched, usernames cross to the core. Passwords
/// cross only for a password file the core reads for an import or writes for
/// an export, and the core keeps none of them.
extension CrestCore {
    // MARK: - Variables

    /// The most records one recency or account question may carry.
    private nonisolated static let credentialBatchLimit = 64

    // MARK: - Actions - Recency

    /// The most recent descriptor, or nil for an empty list. Throws the core's
    /// rejection when it refuses the records.
    nonisolated func mostRecentCredential(
        _ descriptors: [CredentialDescriptor]
    ) throws(Rejection) -> CredentialDescriptor? {
        try reduceCredentials(descriptors) { batch throws(Rejection) in
            try query(MostRecentCredential(records: batch.map { CredentialRecord($0, includesUsername: false) }))
        }
    }

    /// The most recent descriptor for the same account as `username`, or nil.
    /// Throws the core's rejection when it refuses the records.
    nonisolated func credentialSaveMatch(
        username: String,
        in descriptors: [CredentialDescriptor]
    ) throws(Rejection) -> CredentialDescriptor? {
        try reduceCredentials(descriptors) { batch throws(Rejection) in
            try query(
                CredentialSaveMatch(
                    username: username, records: batch.map { CredentialRecord($0, includesUsername: true) }))
        }
    }

    /// Reduces a list in core-sized batches. The core's winner of winners is
    /// its winner of the whole list, so batching does not change the answer.
    nonisolated private func reduceCredentials(
        _ descriptors: [CredentialDescriptor],
        choose: ([CredentialDescriptor]) throws(Rejection) -> CredentialChoice
    ) throws(Rejection) -> CredentialDescriptor? {
        func winner(of batch: [CredentialDescriptor]) throws(Rejection) -> CredentialDescriptor? {
            guard let id = try choose(batch).credentialID else { return nil }
            guard let descriptor = batch.first(where: { $0.id == id }) else {
                preconditionFailure("The core chose a credential it was not asked about.")
            }
            return descriptor
        }
        var remaining = descriptors
        while remaining.count > Self.credentialBatchLimit {
            var winners: [CredentialDescriptor] = []
            for start in stride(from: 0, to: remaining.count, by: Self.credentialBatchLimit) {
                let batch = Array(remaining[start..<min(start + Self.credentialBatchLimit, remaining.count)])
                if let descriptor = try winner(of: batch) { winners.append(descriptor) }
            }
            remaining = winners
        }
        return try winner(of: remaining)
    }
}
