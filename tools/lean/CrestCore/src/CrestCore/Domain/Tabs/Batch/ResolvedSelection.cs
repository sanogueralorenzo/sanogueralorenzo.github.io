using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A selection resolved in the Space it was made in: what the person picked
/// that no picked folder holds, in the order the sidebar lists it, every
/// folder the selection holds, and the tabs it holds, root by root.
public sealed class ResolvedSelection {
    #region Types

    /// A picked tab or folder that no picked folder holds, as the sidebar row
    /// that stands for it.
    public sealed record Root(Guid Id, SidebarRowKind Kind) {
        #region Variables

        /// The pick is a folder, which moves with everything in it.
        public bool IsFolder => Kind.OpensList;

        #endregion
    }

    #endregion

    #region Variables

    /// What the person picked that no picked folder holds, in sidebar order.
    public IReadOnlyList<Root> Roots { get; }

    /// The picked folders and every folder inside them.
    public IReadOnlySet<Guid> Folders { get; }

    /// The tabs the selection holds: each picked tab, and each folder's tabs.
    public IReadOnlyList<BrowserTab> Members { get; }

    /// The members' identities, in the same order.
    public IReadOnlyList<Guid> MemberIds { get; }

    /// Whether the selection holds folders, which only filing and keeping
    /// pages loaded act on.
    public bool HoldsFolders => Folders.Count > 0;

    #endregion

    #region Constructors

    internal ResolvedSelection(IReadOnlyList<Root> roots, IReadOnlySet<Guid> folders, IReadOnlyList<BrowserTab> members) {
        Roots = roots;
        Folders = folders;
        Members = members;
        MemberIds = [.. members.Select(tab => tab.Id)];
    }

    #endregion

    #region Actions - Membership

    /// Whether the selection holds the tab.
    public bool Holds(Guid tabId) => MemberIds.Contains(tabId);

    #endregion
}
