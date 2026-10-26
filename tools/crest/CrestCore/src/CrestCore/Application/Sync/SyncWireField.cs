namespace CrestCore.Application;

/// A field of the sync wire records whose value two writers can spell
/// differently for one meaning, and how two of its values compare. Every
/// other field compares as written.
internal sealed class SyncWireField {
    #region Types

    /// How two values of a field compare.
    public enum Kinds {
        /// A UUID, which the writers spell in either letter case.
        Identity,

        /// A date as seconds, which `JSONEncoder` and `JSONSerialization` can
        /// spell differently (811615335.98 against 811615335.98000002); it
        /// compares exactly as a double, without rounding away a real edit.
        Timestamp
    }

    #endregion

    #region Static Variables

    public static readonly SyncWireField Id = new(StoredSessionCodec.Key.Id, Kinds.Identity);
    public static readonly SyncWireField RawValue = new(StoredSessionCodec.Key.RawValue, Kinds.Identity);
    public static readonly SyncWireField ProfileId = new(StoredSessionCodec.Key.ProfileId, Kinds.Identity);
    public static readonly SyncWireField SpaceId = new(StoredSessionCodec.Key.SpaceId, Kinds.Identity);
    /// The device a record's version names and when a tombstone deleted it,
    /// which no stored record carries.
    public static readonly SyncWireField DeviceId = new(SyncJournalRecord.Key.DeviceId, Kinds.Identity);
    public static readonly SyncWireField DeletedAt = new(SyncJournalRecord.Key.DeletedAt, Kinds.Timestamp);
    public static readonly SyncWireField FolderId = new(StoredSessionCodec.Key.FolderId, Kinds.Identity);
    public static readonly SyncWireField ParentId = new(StoredSessionCodec.Key.ParentId, Kinds.Identity);
    public static readonly SyncWireField OrderAnchorTabId = new(StoredSessionCodec.Key.OrderAnchorTabId, Kinds.Identity);
    public static readonly SyncWireField SplitGroupId = new(StoredSessionCodec.Key.SplitGroupId, Kinds.Identity);
    public static readonly SyncWireField LastActivatedAt = new(StoredSessionCodec.Key.LastActivatedAt, Kinds.Timestamp);
    public static readonly SyncWireField PositionModifiedAt = new(StoredSessionCodec.Key.PositionModifiedAt, Kinds.Timestamp);
    public static readonly SyncWireField TitleModifiedAt = new(StoredSessionCodec.Key.TitleModifiedAt, Kinds.Timestamp);
    public static readonly SyncWireField SavedTabsExpansionModifiedAt = new(StoredSessionCodec.Key.SavedTabsExpansionModifiedAt, Kinds.Timestamp);
    public static readonly SyncWireField CollapseModifiedAt = new(StoredSessionCodec.Key.CollapseModifiedAt, Kinds.Timestamp);
    public static readonly SyncWireField IconModifiedAt = new(StoredSessionCodec.Key.IconModifiedAt, Kinds.Timestamp);
    public static readonly SyncWireField TintModifiedAt = new(StoredSessionCodec.Key.TintModifiedAt, Kinds.Timestamp);
    public static readonly SyncWireField ArchivedAt = new(StoredSessionCodec.Key.ArchivedAt, Kinds.Timestamp);
    public static readonly SyncWireField FirstVisitedAt = new(StoredSessionCodec.Key.FirstVisitedAt, Kinds.Timestamp);
    public static readonly SyncWireField LastVisitedAt = new(StoredSessionCodec.Key.LastVisitedAt, Kinds.Timestamp);
    public static readonly SyncWireField CredentialsEnabledModifiedAt = new(StoredSessionCodec.Key.CredentialsEnabledModifiedAt, Kinds.Timestamp);
    public static readonly SyncWireField AccessPolicyModifiedAt = new(StoredSessionCodec.Key.AccessPolicyModifiedAt, Kinds.Timestamp);

    public static IReadOnlyList<SyncWireField> All { get; } = [
        Id, RawValue, ProfileId, SpaceId, DeviceId, FolderId, ParentId, OrderAnchorTabId, SplitGroupId, LastActivatedAt,
        PositionModifiedAt, TitleModifiedAt, SavedTabsExpansionModifiedAt, CollapseModifiedAt, IconModifiedAt, TintModifiedAt,
        ArchivedAt, DeletedAt, FirstVisitedAt, LastVisitedAt, CredentialsEnabledModifiedAt, AccessPolicyModifiedAt
    ];

    /// Every member by its key, since every field of every compared record
    /// asks.
    private static readonly Dictionary<string, SyncWireField> ByName = All.ToDictionary(field => field.Name, StringComparer.Ordinal);

    #endregion

    #region Variables

    /// The field's key in a wire record.
    public string Name { get; }

    public Kinds Kind { get; }

    #endregion

    #region Constructors

    private SyncWireField(string name, Kinds kind) {
        Name = name;
        Kind = kind;
    }

    #endregion

    #region Actions - Lookup

    public static SyncWireField? Named(string? name) => name is not null && ByName.TryGetValue(name, out var field) ? field : null;

    #endregion
}
