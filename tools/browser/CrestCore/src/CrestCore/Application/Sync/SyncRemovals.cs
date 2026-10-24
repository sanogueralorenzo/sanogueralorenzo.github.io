using CrestCore.Contracts;

namespace CrestCore.Application;

/// The accepted edits one stage covers, oldest first. A burst of edits stages
/// once with the newest edit's reason, but a record an edit removed is deleted
/// for the reason of the edit that removed it, so a Space deletion followed by
/// a rename still deletes the Space explicitly.
internal sealed record SyncRemovals(IReadOnlyList<SyncRemovals.Edit> Edits) {
    #region Types

    /// One accepted edit: the state it replaced, the state it made and the
    /// reason the records it removed are deleted for.
    internal sealed record Edit(SessionState Previous, SessionState Next, SyncDeletionReason Reason);

    #endregion

    #region Variables

    public static SyncRemovals None { get; } = new([]);

    private static readonly IReadOnlyDictionary<string, SyncDeletionReason> Unnamed =
        new Dictionary<string, SyncDeletionReason>(StringComparer.Ordinal);

    #endregion

    #region Actions - Edits

    /// These edits followed by `edit`.
    public SyncRemovals Adding(Edit edit) => new([.. Edits, edit]);

    /// These edits, joined by those of `later` they do not already hold.
    public SyncRemovals Joining(SyncRemovals later) => new([.. Edits, .. later.Edits.Where(edit => !Edits.Contains(edit))]);

    /// The reason each record the edits removed is deleted for, by its record
    /// name: the reason of the newest edit that removed it. Empty when every
    /// edit was made for `reason`, which the stage then gives each removal.
    public IReadOnlyDictionary<string, SyncDeletionReason> Reasons(SyncDeletionReason reason) {
        if (Edits.All(edit => edit.Reason == reason)) return Unnamed;
        var reasons = new Dictionary<string, SyncDeletionReason>(StringComparer.Ordinal);
        foreach (var edit in Edits)
            foreach (var name in Removed(edit.Previous, edit.Next)) reasons[name] = edit.Reason;
        return reasons;
    }

    /// The records `next` no longer holds that `previous` did, as the changes
    /// the session's change feed reports name them.
    private static IEnumerable<string> Removed(SessionState previous, SessionState next) =>
        SessionChanges.Publish(Guid.Empty, previous, next).SelectMany(change => change.RemovedRecords(previous));

    #endregion
}
