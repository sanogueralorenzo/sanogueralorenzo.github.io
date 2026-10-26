namespace CrestCore.Contracts;

/// What one sidebar row stands for: a tab, a folder, or the tabs of a split
/// shown together. A kind travels as its index in `All`, so `All` is
/// append-only.
public sealed class SidebarRowKind {
    #region Static Variables

    public static readonly SidebarRowKind Tab = new(name: "tab", opensList: false, groupsTabs: false);
    public static readonly SidebarRowKind Folder = new(name: "folder", opensList: true, groupsTabs: false);
    public static readonly SidebarRowKind Split = new(name: "split", opensList: false, groupsTabs: true);

    public static IReadOnlyList<SidebarRowKind> All { get; } = [Tab, Folder, Split];

    #endregion

    #region Variables

    /// How the kind is spelled, which also begins the identity a row animates
    /// by: `tab-`, `folder-` or `split-` and the row's identity.
    public string Name { get; }

    /// The row's inside is a list of its own, which the sidebar shows unless
    /// the row is collapsed.
    public bool OpensList { get; }

    /// The row's identity names a split group, and its members are the group's
    /// tabs, shown together.
    public bool GroupsTabs { get; }

    #endregion

    #region Constructors

    private SidebarRowKind(string name, bool opensList, bool groupsTabs) {
        Name = name;
        OpensList = opensList;
        GroupsTabs = groupsTabs;
    }

    #endregion

    #region Actions - Lookup

    public static SidebarRowKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
