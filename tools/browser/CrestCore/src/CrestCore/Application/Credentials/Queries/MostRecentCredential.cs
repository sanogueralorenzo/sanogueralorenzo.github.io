using CrestCore.Application;

namespace CrestCore.Contracts;

/// The most recent of a batch of saved credentials. The records need no
/// usernames. Winners of separate batches reduce to the same answer as one
/// batch, so a caller may split a list longer than the batch limit.
public sealed record MostRecentCredential(IReadOnlyList<CredentialRecord> Records) : Query<CredentialChoice> {
    #region Actions - Answering

    internal override CredentialChoice Answer(CrestApp app) {
        return new(CredentialRecord.MostRecent(Records)?.Id);
    }

    #endregion
}
