namespace CrestCore.Contracts;

/// A kind of record sync carries: its name, which a record's identity and the
/// journal spell, the CloudKit record type it travels as, whether a record of
/// the kind is its Space, and whether one may move to another Space.
///
/// A kind travels as its index in `All`, so `All` is append-only.
public sealed class SyncRecordKind {
    #region Static Variables

    public static readonly SyncRecordKind Space = new(name: "space", cloudRecordType: "CrestSpace", namesItsSpace: true,
        movesBetweenSpaces: false);
    public static readonly SyncRecordKind Folder = new(name: "folder", cloudRecordType: "CrestFolder", namesItsSpace: false,
        movesBetweenSpaces: false);
    public static readonly SyncRecordKind Tab = new(name: "tab", cloudRecordType: "CrestTab", namesItsSpace: false,
        movesBetweenSpaces: true);
    public static readonly SyncRecordKind History = new(name: "history", cloudRecordType: "CrestHistory", namesItsSpace: false,
        movesBetweenSpaces: false);
    public static readonly SyncRecordKind Archive = new(name: "archive", cloudRecordType: "CrestArchive", namesItsSpace: false,
        movesBetweenSpaces: true);

    public static IReadOnlyList<SyncRecordKind> All { get; } = [Space, Folder, Tab, History, Archive];

    #endregion

    #region Variables

    /// How a record's identity and the journal spell the kind.
    public string Name { get; }

    /// The CloudKit record type a record of the kind travels as.
    public string CloudRecordType { get; }

    /// A record of the kind is its Space, so its identity is its Space's.
    public bool NamesItsSpace { get; }

    /// A record of the kind keeps its identity when it moves to another Space,
    /// as a tab and its archive do, so two copies of one may name different
    /// Spaces.
    public bool MovesBetweenSpaces { get; }

    #endregion

    #region Constructors

    private SyncRecordKind(string name, string cloudRecordType, bool namesItsSpace, bool movesBetweenSpaces) {
        Name = name;
        CloudRecordType = cloudRecordType;
        NamesItsSpace = namesItsSpace;
        MovesBetweenSpaces = movesBetweenSpaces;
    }

    #endregion

    #region Actions - Lookup

    public static SyncRecordKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    /// The journal's name for the record of this kind `id` names.
    internal string RecordName(Guid id) => RecordPrefix + id.ToString("D");

    /// How every record name of this kind begins in the journal.
    internal string RecordPrefix => Name + ":";

    #endregion
}
