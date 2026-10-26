using CrestCore.Contracts;

namespace CrestCore.Application;

/// How an accepted revision reaches the sync journal: why the records it
/// removed are deleted, and how soon it stages.
internal sealed record SyncStaging(SyncDeletionReason Reason, SyncUrgency Urgency) {
    #region Static Variables

    /// A launch stages the session it loaded; what the file lost while the app
    /// was closed was removed by retention.
    public static SyncStaging Launch { get; } = new(SyncDeletionReason.Retention, SyncUrgency.Immediate);

    /// A window showed a tab, which records when it was used.
    public static SyncStaging TabUse { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Deferred);

    /// A page reported where a navigation landed or which icon it shows, or a
    /// tab took an address to load.
    public static SyncStaging PageReport { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Deferred);

    /// A tab moved between workspaces.
    public static SyncStaging Transfer { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.WithSave);

    /// A person acted on the tabs they selected together: saved with its
    /// journal before the intent returns.
    public static SyncStaging Batch { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.WithSave);

    /// A person deleted the tabs they selected together: saved with its
    /// journal, as deletions, before the intent returns.
    public static SyncStaging BatchDeletion { get; } = new(SyncDeletionReason.ExplicitDelete, SyncUrgency.WithSave);

    /// The person deleted records: history, or a folder.
    public static SyncStaging Deletion { get; } = new(SyncDeletionReason.ExplicitDelete, SyncUrgency.Immediate);

    /// Records aged out under their Space's retention, or open tabs its
    /// cleanup archived.
    public static SyncStaging Expiry { get; } = new(SyncDeletionReason.Retention, SyncUrgency.Immediate);

    /// Something another device should see soon: a new folder or a restored tab.
    public static SyncStaging Creation { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Immediate);

    /// An organizing edit, staged once edits pause: a rename, a move or a split.
    public static SyncStaging Edit { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Coalesced);

    /// Who may open a Space, or whether it uses Crest Passwords, changed:
    /// another device should see it soon.
    public static SyncStaging Protection { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.Immediate);

    /// A Space's deletion began. It is saved with its journal before the
    /// platform erases the profile's data.
    public static SyncStaging Withdrawal { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.WithSave);

    /// A Space whose profile's data was erased went, with its records, saved
    /// with its journal before the intent returns.
    public static SyncStaging Removal { get; } = new(SyncDeletionReason.ExplicitDelete, SyncUrgency.WithSave);

    /// Spaces were imported, saved with their journal before the import
    /// returns, because an upload follows.
    public static SyncStaging Import { get; } = new(SyncDeletionReason.Superseded, SyncUrgency.WithSave);

    #endregion
}
