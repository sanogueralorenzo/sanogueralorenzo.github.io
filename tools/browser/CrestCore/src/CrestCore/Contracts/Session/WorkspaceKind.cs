namespace CrestCore.Contracts;

/// What a workspace's session is: the persistent session this device keeps, a
/// private one that keeps nothing, a borrowed one that shows a Space of
/// another workspace with its own tabs and keeps nothing, or the Getting
/// Started practice, which keeps nothing either. Each kind carries the
/// rules that differ by kind, so a handler reads them instead of naming a kind.
///
/// A kind travels as its index in `All`, so `All` is append-only.
public sealed class WorkspaceKind {
    #region Static Variables

    public static readonly WorkspaceKind Persistent = new(name: "persistent", opensDirectly: true, keepsFile: true,
        isPrivate: false, ownsSpaces: true, keepsAppPreferences: true, isPractice: false, sharesPagesAcrossWindows: true);
    public static readonly WorkspaceKind Private = new(name: "private", opensDirectly: true, keepsFile: false,
        isPrivate: true, ownsSpaces: true, keepsAppPreferences: false, isPractice: false, sharesPagesAcrossWindows: false);
    public static readonly WorkspaceKind Borrowed = new(name: "borrowed", opensDirectly: false, keepsFile: false,
        isPrivate: false, ownsSpaces: false, keepsAppPreferences: false, isPractice: false, sharesPagesAcrossWindows: false);
    public static readonly WorkspaceKind Practice = new(name: "practice", opensDirectly: true, keepsFile: false,
        isPrivate: false, ownsSpaces: true, keepsAppPreferences: false, isPractice: true, sharesPagesAcrossWindows: false);

    public static IReadOnlyList<WorkspaceKind> All { get; } = [Persistent, Private, Borrowed, Practice];

    #endregion

    #region Variables

    public string Name { get; }

    /// A workspace of this kind opens by itself, from a seed or from where its
    /// first session comes from. One that does not opens only by borrowing a
    /// Space of another workspace.
    public bool OpensDirectly { get; }

    /// Opened without a seed, a workspace of this kind is the session the core
    /// keeps in its file: every accepted edit is saved there, and its sync
    /// journal is kept and staged beside it. Opened from a seed, it keeps
    /// nothing. A kind that keeps no file is never saved or synced, and opened
    /// without a seed it starts from the Space template of its kind.
    public bool KeepsFile { get; }

    /// Pages in the workspace keep nothing once they close, its Spaces are
    /// private ones, and it may start over.
    public bool IsPrivate { get; }

    /// The workspace owns its Spaces' profiles: it makes, orders and deletes
    /// Spaces and changes their settings. One that does not borrows its Space
    /// from the workspace that owns it.
    public bool OwnsSpaces { get; }

    /// The workspace keeps the app-wide preferences and takes imported Spaces.
    public bool KeepsAppPreferences { get; }

    /// The workspace is the Getting Started practice: opened without a seed,
    /// it starts from the practice Space and its tabs, not its kind's Space
    /// template.
    public bool IsPractice { get; }

    /// The workspace's windows share its pages where the device lets them, so
    /// a page outlives the window that hosts it: the workspace's other windows
    /// show it, or its next window does. A page of a kind that does not, such
    /// as the private window's or a torn-off tab's, goes with its window. The
    /// core's own rule, which no platform reads.
    internal bool SharesPagesAcrossWindows { get; }

    #endregion

    #region Constructors

    private WorkspaceKind(string name, bool opensDirectly, bool keepsFile, bool isPrivate, bool ownsSpaces,
        bool keepsAppPreferences, bool isPractice, bool sharesPagesAcrossWindows) {
        Name = name;
        OpensDirectly = opensDirectly;
        KeepsFile = keepsFile;
        IsPrivate = isPrivate;
        OwnsSpaces = ownsSpaces;
        KeepsAppPreferences = keepsAppPreferences;
        IsPractice = isPractice;
        SharesPagesAcrossWindows = sharesPagesAcrossWindows;
    }

    #endregion

    #region Actions - Lookup

    public static WorkspaceKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
