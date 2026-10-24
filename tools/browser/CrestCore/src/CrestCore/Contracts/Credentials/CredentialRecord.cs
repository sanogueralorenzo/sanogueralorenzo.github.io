using System.Text;

namespace CrestCore.Contracts;

/// A saved credential's identity and recency metadata. It never carries the
/// secret. `Username` is only needed where a rule matches accounts; dates are
/// in seconds since 1970. The most recent record is the one with the latest
/// use, or the latest update for one never used, with the identity breaking
/// exact ties so every caller picks the same record. Accounts match by
/// username without regard to case.
public sealed record CredentialRecord(Guid Id, string? Username, double UpdatedAt, double? LastUsedAt) {
    #region Static Variables

    /// The most records one question may carry.
    internal const int MaximumRecords = 64;

    internal const int MaximumUsernameLength = 4_096;

    #endregion

    #region Variables

    /// The moment the credential was last relevant to the person.
    public double RecencyDate => LastUsedAt ?? UpdatedAt;

    #endregion

    #region Actions - Recency

    internal bool IsLessRecentThan(CredentialRecord other) {
        ArgumentNullException.ThrowIfNull(other);
        double left = CredentialPendingCandidate.Seconds(RecencyDate), right = CredentialPendingCandidate.Seconds(other.RecencyDate);
        if (left != right) return left < right;
        return string.CompareOrdinal(Id.ToString("D"), other.Id.ToString("D")) < 0;
    }

    /// Null when there are no records. Winners of separate batches reduce to
    /// the same answer as one batch, so callers may split long lists.
    internal static CredentialRecord? MostRecent(IReadOnlyList<CredentialRecord> records) {
        ArgumentNullException.ThrowIfNull(records);
        if (records.Count > MaximumRecords) throw new Rejected(new CredentialRecordLimitReached(MaximumRecords));
        if (records.Select(record => record.Id).Distinct().Count() != records.Count) throw new Rejected(new DuplicateCredential());
        CredentialRecord? best = null;
        foreach (var record in records) {
            _ = CredentialPendingCandidate.Seconds(record.UpdatedAt);
            if (best is null || best.IsLessRecentThan(record)) best = record;
        }
        return best;
    }

    #endregion

    #region Actions - Saving

    /// The most recent record whose username names the same account as
    /// `username`, or null. Usernames are compared after canonical
    /// composition, ignoring case; a record without a username is refused, and
    /// an empty one never matches. The stored secret stays with the platform:
    /// it compares the candidate against the matched record and reports only
    /// whether the passwords are equal.
    internal static CredentialRecord? Matching(string username, IReadOnlyList<CredentialRecord> records) {
        ArgumentNullException.ThrowIfNull(username);
        ArgumentNullException.ThrowIfNull(records);
        if (username.Length is 0 or > MaximumUsernameLength) throw new Rejected(new InvalidCredentialUsername());
        if (records.Count > MaximumRecords) throw new Rejected(new CredentialRecordLimitReached(MaximumRecords));
        if (records.Any(record => record.Username is null)) throw new Rejected(new InvalidCredentialRecord());
        if (records.Any(record => record.Username!.Length > MaximumUsernameLength)) throw new Rejected(new InvalidCredentialUsername());
        string account = Account(username);
        return MostRecent(records
            .Where(record => string.Equals(Account(record.Username!), account, StringComparison.OrdinalIgnoreCase))
            .ToArray());
    }

    private static string Account(string username) => username.Normalize(NormalizationForm.FormC);

    #endregion
}
