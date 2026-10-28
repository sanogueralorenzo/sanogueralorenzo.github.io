using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The same bounded forest and stable tab-boundary ordering used by Crest's native sidebars.
/// A tree reads its folders as they stand when it is made.
public sealed class FolderTree(IReadOnlyList<FolderState> folders) {
    #region Static Variables

    public const int MaximumDepth = FolderState.MaximumDepth;
    public const int MaximumCount = 500;

    #endregion

    #region Variables

    /// Each folder by its identity, the first of any that share one, so a
    /// lookup never searches the list.
    private readonly Dictionary<Guid, FolderState> byId = Index(folders);

    #endregion

    #region Actions - Organization

    private static Dictionary<Guid, FolderState> Index(IReadOnlyList<FolderState> folders) {
        ArgumentNullException.ThrowIfNull(folders);
        var index = new Dictionary<Guid, FolderState>(folders.Count);
        foreach (var folder in folders) index.TryAdd(folder.Id, folder);
        return index;
    }

    /// The bounded tree `source` makes, in preorder: a folder whose parent
    /// comes later, is missing or would sit too deep moves to the top level,
    /// a child takes its parent's section, and a folder that repeats an
    /// identity, sits in a section that holds no folders or comes past the
    /// most a Space keeps is left out. Never throws.
    public static IReadOnlyList<FolderState> RepairPreorder(IReadOnlyList<FolderState> source) {
        List<FolderState> accepted = [];
        Dictionary<Guid, (int Depth, TabPlacement Location)> parents = [];
        foreach (var folder in source) {
            if (accepted.Count == MaximumCount) break;
            if (parents.ContainsKey(folder.Id)) continue;
            var parent = folder.ParentId;
            if (parent is not { } requested || requested == folder.Id || !parents.TryGetValue(requested, out var found)
                || found.Depth + 1 >= MaximumDepth) parent = null;
            var repaired = folder with { ParentId = parent, Location = parent is { } p ? parents[p].Location : folder.Location };
            if (!repaired.Location.HoldsFolders) continue;
            accepted.Add(repaired);
            parents[folder.Id] = (parent is { } id ? parents[id].Depth + 1 : 0, repaired.Location);
        }
        return new FolderTree(accepted).DisplayOrder();
    }

    /// Throws `BrowserRuleException` with `InvalidFolderTree` unless the
    /// folders are a bounded tree: too many, a repeated identity, a folder in
    /// a section that holds none, a parent that is missing or in another
    /// section, a cycle, or a folder too deep.
    public void Validate() {
        if (folders.Count > MaximumCount || folders.Select(f => f.Id).Distinct().Count() != folders.Count)
            throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
        foreach (var folder in folders) {
            if (!folder.Location.HoldsFolders
                || folder.ParentId is { } parent && (!byId.TryGetValue(parent, out var held) || held.Location != folder.Location))
                throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
            _ = Depth(folder.Id);
        }
    }

    public IReadOnlyList<FolderState> DisplayOrder() {
        Validate(); List<FolderState> result = [];
        void Append(Guid? parent) {
            foreach (var folder in Children(parent)) { result.Add(folder); Append(folder.Id); }
        }
        Append(null); return [.. result];
    }

    public HashSet<Guid> EmptyPredecessors(Guid? before, Guid? anchor, Guid? parent,
        TabPlacement placement, IReadOnlyList<BrowserTab> tabs) {
        HashSet<Guid> result = [];
        var target = before is { } id ? Subtree(id) : [];
        bool targetEmpty = !tabs.Any(tab => tab.FolderId is { } folderId && target.Contains(folderId));
        foreach (var folder in Children(parent).Where(f => f.Location == placement)) {
            if (folder.Id == before && targetEmpty) break;
            var subtree = Subtree(folder.Id);
            if (!tabs.Any(tab => tab.FolderId is { } folderId && subtree.Contains(folderId)) && TabAnchor(folder.Id, tabs) == anchor)
                result.Add(folder.Id);
        }
        return result;
    }

    public List<FolderState> PreserveOrder(HashSet<Guid> removed, IReadOnlyList<BrowserTab> tabs,
        HashSet<Guid>? excluding = null) => folders.Select(folder => {
            if (excluding?.Contains(folder.Id) == true) return folder;
            var subtree = Subtree(folder.Id);
            var members = tabs.Where(tab => tab.FolderId is { } folderId && subtree.Contains(folderId)).ToArray();
            if (members.Any(tab => !removed.Contains(tab.Id))) return folder;
            var old = members.FirstOrDefault()?.Id ?? folder.OrderAnchorTabId;
            if (old is not { } anchor || !removed.Contains(anchor)) return folder;
            int start = tabs.ToList().FindIndex(tab => tab.Id == anchor);
            if (start < 0) return folder;
            var parent = folder.ParentId is { } p ? Subtree(p) : null;
            return folder with {
                OrderAnchorTabId = tabs.Skip(start).FirstOrDefault(tab => !removed.Contains(tab.Id)
                && tab.Placement == folder.Location && (parent is null || tab.FolderId is { } folderId && parent.Contains(folderId)))?.Id
            };
        }).ToList();

    #endregion

    #region Mutators

    /// The folder with this identity. Refused with `UnknownFolder` for one the
    /// tree does not hold.
    public FolderState Folder(Guid id) => byId.TryGetValue(id, out var folder) ? folder
        : throw new Rejected(new UnknownFolder(id));

    public IEnumerable<FolderState> Children(Guid? id) => folders.Where(f => f.ParentId == id);

    public HashSet<Guid> Subtree(Guid id) {
        _ = Folder(id);
        HashSet<Guid> result = []; Stack<Guid> pending = new([id]);
        while (pending.TryPop(out var next))
            if (result.Add(next)) foreach (var child in Children(next)) pending.Push(child.Id);
        return result;
    }

    /// How many folders hold the folder. Refused with `UnknownFolder` for one
    /// the tree does not hold; throws `BrowserRuleException` with
    /// `InvalidFolderTree` when a folder above it is missing, in a cycle or
    /// too deep.
    public int Depth(Guid id) {
        var folder = Folder(id); var depth = 0; HashSet<Guid> seen = [id];
        while (folder.ParentId is { } parent) {
            if (!seen.Add(parent) || ++depth >= MaximumDepth || !byId.TryGetValue(parent, out var held))
                throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
            folder = held;
        }
        return depth;
    }

    /// The titles from the outermost folder down to `id`, joined as a path, as
    /// the palette names where a saved tab lives.
    public string PathTitle(Guid id) {
        var folder = Folder(id);
        List<string> titles = [folder.Title];
        HashSet<Guid> seen = [id];
        while (folder.ParentId is { } parent && seen.Add(parent)) {
            folder = Folder(parent);
            titles.Add(folder.Title);
        }
        titles.Reverse();
        return string.Join(" › ", titles);
    }

    public Guid? TabAnchor(Guid id, IReadOnlyList<BrowserTab> tabs) {
        var subtree = Subtree(id);
        return tabs.FirstOrDefault(tab => tab.FolderId is { } folderId && subtree.Contains(folderId))?.Id
            ?? (Folder(id).OrderAnchorTabId is { } anchor && tabs.Any(tab => tab.Id == anchor) ? anchor : null);
    }

    #endregion
    #region Actions - Sync

    /// Promotes a folder whose parent `missing` a partial delivery left out to
    /// the nearest ancestor still delivered, through parents this device holds
    /// and knows deleted, without confusing an unknown parent with a deleted
    /// one.
    public static bool TryPromote(Guid missing, HashSet<Guid> active,
        IReadOnlyDictionary<Guid, FolderState> local, HashSet<Guid> deleted,
        out Guid? parent) {
        parent = missing;
        HashSet<Guid> seen = [];
        while (parent is { } candidate) {
            if (active.Contains(candidate)) return true;
            if (!deleted.Contains(candidate) || !seen.Add(candidate) || !local.TryGetValue(candidate, out var folder)) return false;
            parent = folder.ParentId;
        }
        return true;
    }

    /// The folders of `space` a delivery holds, in tree order, each whose
    /// parent it left out promoted as `TryPromote` resolves it. The caller
    /// supplies stable sibling order from the sync records.
    public static IReadOnlyList<FolderState> Materialized(Guid space, IReadOnlyList<FolderState> ordered,
        IReadOnlyDictionary<Guid, Guid> owners, IReadOnlyDictionary<Guid, FolderState> local,
        HashSet<Guid> deleted) {
        if (ordered.Count > FolderTree.MaximumCount || ordered.Select(f => f.Id).Distinct().Count() != ordered.Count)
            throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
        var active = ordered.Select(f => f.Id).ToHashSet();
        List<FolderState> roots = [];
        Dictionary<Guid, List<FolderState>> children = [];
        HashSet<Guid> waiting = [];
        foreach (var source in ordered) {
            var folder = source;
            if (folder.ParentId is { } parent) {
                if (parent == folder.Id) throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
                if (!active.Contains(parent)) {
                    if (owners.TryGetValue(parent, out var owner) && owner != space) throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
                    if (!TryPromote(parent, active, local, deleted, out var promoted)) { waiting.Add(folder.Id); continue; }
                    folder = folder with { ParentId = promoted };
                }
            }
            if (folder.ParentId is { } resolved) {
                if (!children.TryGetValue(resolved, out var siblings)) children[resolved] = siblings = [];
                siblings.Add(folder);
            } else roots.Add(folder);
        }
        HashSet<Guid> visited = [];
        List<FolderState> result = [];
        void Append(FolderState folder, int depth) {
            if (depth >= FolderTree.MaximumDepth || !visited.Add(folder.Id)) throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
            result.Add(folder);
            foreach (var child in children.GetValueOrDefault(folder.Id) ?? []) Append(child, depth + 1);
        }
        foreach (var root in roots) Append(root, 0);
        Stack<Guid> pending = new(waiting);
        while (pending.TryPop(out var next))
            foreach (var child in children.GetValueOrDefault(next) ?? []) if (waiting.Add(child.Id)) pending.Push(child.Id);
        if (visited.Count + waiting.Count != ordered.Count) throw new BrowserRuleException(BrowserRule.InvalidFolderTree);
        new FolderTree(result).Validate();
        return result;
    }

    #endregion
}
