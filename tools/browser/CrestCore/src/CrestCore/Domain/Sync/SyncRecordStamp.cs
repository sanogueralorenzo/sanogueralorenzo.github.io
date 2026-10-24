using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What conflict resolution reads of one version of a record. `ActivatedAt` is
/// when an open tab was last shown, and null for any other record. Conflict
/// decisions are shared by every engine and cloud transport.
public sealed record SyncRecordStamp(SyncRecordKind Kind, Guid Id, Guid Space, SyncVersion Version,
    SyncDeletionReason? DeletionReason, double? DeletedAt, double? ActivatedAt) {
    #region Actions - Conflicts

    /// Which of two copies of one record wins: 0 for `first`, 1 for `second`.
    /// Copies of a kind that moves between Spaces may name different Spaces
    /// and are decided as any other two.
    public static int Winner(SyncRecordStamp first, SyncRecordStamp second) {
        if (first.Id != second.Id || first.Kind != second.Kind || (first.Space != second.Space && !first.Kind.MovesBetweenSpaces))
            throw new BrowserRuleException(BrowserRule.SyncIdentityMismatch);
        if (first.DeletionReason?.IsExplicit == true) return 0;
        if (second.DeletionReason?.IsExplicit == true) return 1;
        // A tab shown after the other side deleted it stays open.
        if (first.DeletedAt is { } firstDeleted && second.ActivatedAt > firstDeleted) return 1;
        if (second.DeletedAt is { } secondDeleted && first.ActivatedAt > secondDeleted) return 0;
        return first.Version.CompareTo(second.Version) < 0 ? 1 : 0;
    }

    /// Which of two copies' edit dates for one field is later: 0 for `first`,
    /// 1 for `second`, or null when they are equal. A copy with no date loses.
    public static int? Later(double? first, double? second) {
        if (first == second) return null;
        if (first is null) return 1;
        if (second is null) return 0;
        return first > second ? 0 : 1;
    }

    #endregion
}
