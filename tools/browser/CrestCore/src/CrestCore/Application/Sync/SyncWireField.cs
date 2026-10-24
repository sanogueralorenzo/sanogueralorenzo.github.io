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

    public static readonly SyncWireField Id = new("id", Kinds.Identity);
    public static readonly SyncWireField RawValue = new("rawValue", Kinds.Identity);
    public static readonly SyncWireField ProfileId = new("profileID", Kinds.Identity);
    public static readonly SyncWireField SpaceId = new("spaceID", Kinds.Identity);
    public static readonly SyncWireField DeviceId = new("deviceID", Kinds.Identity);
    public static readonly SyncWireField FolderId = new("folderID", Kinds.Identity);
    public static readonly SyncWireField ParentId = new("parentID", Kinds.Identity);
    public static readonly SyncWireField OrderAnchorTabId = new("orderAnchorTabID", Kinds.Identity);
    public static readonly SyncWireField SplitGroupId = new("splitGroupID", Kinds.Identity);
    public static readonly SyncWireField LastActivatedAt = new("lastActivatedAt", Kinds.Timestamp);
    public static readonly SyncWireField PositionModifiedAt = new("positionModifiedAt", Kinds.Timestamp);
    public static readonly SyncWireField TitleModifiedAt = new("titleModifiedAt", Kinds.Timestamp);
    public static readonly SyncWireField SavedTabsExpansionModifiedAt = new("savedTabsExpansionModifiedAt", Kinds.Timestamp);
    public static readonly SyncWireField CollapseModifiedAt = new("collapseModifiedAt", Kinds.Timestamp);
    public static readonly SyncWireField IconModifiedAt = new("iconModifiedAt", Kinds.Timestamp);
    public static readonly SyncWireField TintModifiedAt = new("tintModifiedAt", Kinds.Timestamp);
    public static readonly SyncWireField ArchivedAt = new("archivedAt", Kinds.Timestamp);
    public static readonly SyncWireField DeletedAt = new("deletedAt", Kinds.Timestamp);
    public static readonly SyncWireField FirstVisitedAt = new("firstVisitedAt", Kinds.Timestamp);
    public static readonly SyncWireField LastVisitedAt = new("lastVisitedAt", Kinds.Timestamp);
    public static readonly SyncWireField CredentialsEnabledModifiedAt = new("credentialsEnabledModifiedAt", Kinds.Timestamp);
    public static readonly SyncWireField AccessPolicyModifiedAt = new("accessPolicyModifiedAt", Kinds.Timestamp);

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
