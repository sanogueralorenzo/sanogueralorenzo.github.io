namespace CrestCore.Contracts;

/// <summary>
/// What a Space's sidebar lists, in pieces a platform observes apart: the top level of
/// each section in <see cref="TabPlacement.All"/> order, then the inside of each folder
/// in the order the Space keeps its folders. A list holds its rows whether or not its
/// folder or section is collapsed; <see cref="Shown"/> is what a person sees.
/// </summary>
/// <remarks>
/// A Start Page is listed nowhere. A section that holds splits shows the first run of
/// at least <see cref="SplitGroupState.MinimumShownMembers"/> tabs of one split as one
/// row, and a split folds once. A section that holds folders lists each folder where
/// its first row falls in the Space's tab order; a folder without rows keeps its place
/// before the row holding the tab it anchors to, or else ends its list.
/// </remarks>
public sealed record SidebarOutline(IReadOnlyList<SidebarList> Lists) {
    #region Types

    /// A folder in the order the sidebar lists folders, with how many folders hold it.
    private readonly record struct FolderNode(FolderState Folder, int Depth);

    /// A row before it is placed in a list: the folder its first tab lives in decides
    /// where it goes.
    private readonly record struct Item(Guid Id, SidebarRowKind Kind, Guid? FolderId, IReadOnlyList<Guid> Members) {
        public static Item Of(TabState tab) => new(tab.Id, SidebarRowKind.Tab, tab.FolderId, [tab.Id]);

        public SidebarRow Row(Guid? parentFolderId, int depth) => new(Id, Kind, parentFolderId, depth, Members);
    }

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SidebarList> Lists {
        get;
        init => field = [.. value];
    } = [.. Lists];

    #endregion

    #region Actions - Building

    /// <summary>The outline a Space with these tabs and folders shows.</summary>
    public static SidebarOutline Of(IReadOnlyList<TabState> tabs, IReadOnlyList<FolderState> folders) {
        ArgumentNullException.ThrowIfNull(tabs);
        ArgumentNullException.ThrowIfNull(folders);
        var nodes = FolderNodes(folders);
        var insides = new Dictionary<Guid, List<SidebarRow>>();
        var lists = new List<SidebarList>(TabPlacement.All.Count + folders.Count);
        foreach (var section in TabPlacement.All) {
            var listed = new List<TabState>();
            foreach (var tab in tabs)
                if (tab.Placement == section && !tab.IsStartPage) listed.Add(tab);
            var items = Fold(listed, section.HoldsSplits);
            IReadOnlyList<SidebarRow> top = section.HoldsFolders
                ? [.. Nest(section, items, listed, nodes, insides)]
                : [.. items.Select(item => item.Row(parentFolderId: null, depth: 0))];
            lists.Add(new SidebarList(section, FolderId: null, top));
        }
        var seen = new HashSet<Guid>();
        foreach (var folder in folders)
            if (seen.Add(folder.Id))
                lists.Add(new SidebarList(folder.Location, folder.Id, insides.TryGetValue(folder.Id, out var rows) ? [.. rows] : []));
        return new([.. lists]);
    }

    /// The folders the sidebar can list, top-level folders first in the Space's order,
    /// each followed by its own folders, as deep as a folder may nest.
    private static List<FolderNode> FolderNodes(IReadOnlyList<FolderState> folders) {
        var children = new Dictionary<Guid, List<FolderState>>();
        var roots = new List<FolderState>();
        var known = new HashSet<Guid>();
        foreach (var folder in folders) {
            if (!known.Add(folder.Id)) continue;
            if (folder.ParentId is { } parent) {
                if (!children.TryGetValue(parent, out var siblings)) children[parent] = siblings = [];
                siblings.Add(folder);
            } else {
                roots.Add(folder);
            }
        }
        var nodes = new List<FolderNode>(folders.Count);
        var visited = new HashSet<Guid>();
        void Append(FolderState folder, int depth) {
            if (depth >= FolderState.MaximumDepth || !visited.Add(folder.Id)) return;
            nodes.Add(new(folder, depth));
            if (children.TryGetValue(folder.Id, out var inside))
                foreach (var child in inside) Append(child, depth + 1);
        }
        foreach (var root in roots) Append(root, 0);
        return nodes;
    }

    /// A section's tabs as the rows they show, in order. When the section holds splits,
    /// the first run of enough tabs of one split is one row, and a split folds once:
    /// a later run of it shows as plain tabs.
    private static List<Item> Fold(List<TabState> listed, bool holdsSplits) {
        var items = new List<Item>(listed.Count);
        HashSet<Guid>? folded = null;
        int index = 0;
        while (index < listed.Count) {
            var tab = listed[index];
            if (!holdsSplits || tab.SplitGroupId is not { } group || folded?.Contains(group) == true) {
                items.Add(Item.Of(tab));
                index++;
                continue;
            }
            int end = index + 1;
            while (end < listed.Count && listed[end].SplitGroupId == group) end++;
            if (end - index >= SplitGroupState.MinimumShownMembers) {
                IReadOnlyList<Guid> members = [.. listed[index..end].Select(member => member.Id)];
                items.Add(new Item(group, SidebarRowKind.Split, tab.FolderId, members));
                (folded ??= []).Add(group);
            } else {
                for (int member = index; member < end; member++) items.Add(Item.Of(listed[member]));
            }
            index = end;
        }
        return items;
    }

    /// Places a section's rows in its top level and its folders' insides, which it adds
    /// to `insides`, and answers the top level. Each row goes inside the folder of its
    /// first tab, and each folder on its way there takes the place of that row in its
    /// own parent the first time a row reaches it. A folder no row reaches goes before
    /// the row that holds, or the folder that contains, the tab it anchors to, or else
    /// last. A row whose folder the section does not hold is listed nowhere.
    private static List<SidebarRow> Nest(TabPlacement section, List<Item> items, List<TabState> listed, List<FolderNode> nodes,
        Dictionary<Guid, List<SidebarRow>> insides) {
        var byId = new Dictionary<Guid, FolderNode>();
        var paths = new Dictionary<Guid, Guid[]>();
        foreach (var node in nodes) {
            if (node.Folder.Location != section) continue;
            byId[node.Folder.Id] = node;
            paths[node.Folder.Id] = node.Folder.ParentId is { } parent && paths.TryGetValue(parent, out var above)
                ? [.. above, node.Folder.Id]
                : [node.Folder.Id];
        }
        var top = new List<SidebarRow>();
        List<SidebarRow> Rows(Guid? folderId) {
            if (folderId is not { } id) return top;
            if (!insides.TryGetValue(id, out var rows)) insides[id] = rows = [];
            return rows;
        }
        var reached = new HashSet<Guid>();
        foreach (var item in items) {
            Guid[] path = [];
            if (item.FolderId is { } folderId) {
                if (!paths.TryGetValue(folderId, out var found)) continue;
                path = found;
            }
            Guid? above = null;
            foreach (var id in path) {
                if (reached.Add(id)) Rows(above).Add(FolderRow(byId[id], above));
                above = id;
            }
            Rows(item.FolderId).Add(item.Row(item.FolderId, item.FolderId is { } parent ? byId[parent].Depth + 1 : 0));
        }
        Dictionary<Guid, Guid?>? tabFolders = null;
        foreach (var node in nodes) {
            var folder = node.Folder;
            if (folder.Location != section || reached.Contains(folder.Id)) continue;
            if (folder.ParentId is { } parent && !byId.ContainsKey(parent)) continue;
            var rows = Rows(folder.ParentId);
            int index = -1;
            if (folder.OrderAnchorTabId is { } anchor) {
                tabFolders ??= listed.ToDictionary(tab => tab.Id, tab => tab.FolderId);
                Guid[] anchorPath = tabFolders.TryGetValue(anchor, out var anchorFolder) && anchorFolder is { } id
                    && paths.TryGetValue(id, out var found) ? found : [];
                index = rows.FindIndex(row => row.Kind.OpensList ? anchorPath.Contains(row.Id) : row.Members.Contains(anchor));
            }
            rows.Insert(index < 0 ? rows.Count : index, FolderRow(node, folder.ParentId));
        }
        return top;
    }

    private static SidebarRow FolderRow(FolderNode node, Guid? parentFolderId) =>
        new(node.Folder.Id, SidebarRowKind.Folder, parentFolderId, node.Depth, []);

    #endregion

    #region Actions - Reading

    /// <summary>Where each tab and folder falls in the sidebar's order, counting from
    /// zero: each section in turn, and each folder followed by its inside, collapsed or
    /// not. A Start Page has no place.</summary>
    public Dictionary<Guid, int> Positions() {
        var positions = new Dictionary<Guid, int>();
        foreach (var id in Walk(_ => true, _ => true)) positions.TryAdd(id, positions.Count);
        return positions;
    }

    /// <summary>The tabs and folders a person sees, in order: the sections
    /// <paramref name="isSectionExpanded"/> answers for, skipping the inside of every folder
    /// of <paramref name="folders"/> that is collapsed.</summary>
    public IEnumerable<Guid> Shown(IReadOnlyList<FolderState> folders, Func<TabPlacement, bool> isSectionExpanded) {
        ArgumentNullException.ThrowIfNull(folders);
        ArgumentNullException.ThrowIfNull(isSectionExpanded);
        var collapsed = Collapsed(folders);
        return Walk(isSectionExpanded, id => !collapsed.Contains(id));
    }

    /// <summary>The rows a person steps through, in the order the sidebar shows them: each
    /// tab and split row of the sections <paramref name="isSectionExpanded"/> answers for,
    /// skipping the inside of every folder of <paramref name="folders"/> that is collapsed.
    /// A split is one stop; a folder and a Start Page are none.</summary>
    public IReadOnlyList<SidebarRow> Stops(IReadOnlyList<FolderState> folders, Func<TabPlacement, bool> isSectionExpanded) {
        ArgumentNullException.ThrowIfNull(folders);
        ArgumentNullException.ThrowIfNull(isSectionExpanded);
        var collapsed = Collapsed(folders);
        return [.. Rows(isSectionExpanded, id => !collapsed.Contains(id)).Where(row => !row.Kind.OpensList)];
    }

    /// <summary>The tab one step in <paramref name="direction"/> from the shown tab
    /// <paramref name="shownTabId"/> shows among the <see cref="Stops"/>, wrapping at both
    /// ends: the first tab of the stop the step reaches, or null when there is no stop or
    /// the step reaches the stop that shows it. A tab no stop shows steps from where it
    /// lives in the sidebar's order, inside a collapsed folder or section, or from the ends
    /// when it has no place there, as a Start Page has none.</summary>
    public Guid? Step(Guid shownTabId, AdjacentDirection direction, IReadOnlyList<FolderState> folders,
        Func<TabPlacement, bool> isSectionExpanded) {
        ArgumentNullException.ThrowIfNull(direction);
        var stops = Stops(folders, isSectionExpanded);
        if (stops.Count == 0) return null;
        int shown = -1;
        for (int index = 0; index < stops.Count && shown < 0; index++)
            if (stops[index].Members.Contains(shownTabId)) shown = index;
        int reached;
        if (shown >= 0) {
            reached = direction.From(shown, stops.Count);
        } else {
            var positions = Positions();
            int gap = positions.TryGetValue(shownTabId, out int place) ? stops.Count(stop => positions[stop.Members[0]] < place) : 0;
            reached = direction.FromGap(gap, stops.Count);
        }
        return reached == shown ? null : stops[reached].Members[0];
    }

    /// <summary>The tab a swipe in <paramref name="direction"/> from the shown tab
    /// <paramref name="shownTabId"/> reaches among the <see cref="Stops"/>, which stops at
    /// both ends: the next card of the split that shows it, or past its last card, the
    /// next stop, entered at its nearest card. Null past either end. A tab no stop shows
    /// swipes from where it lives, as <see cref="Step"/> steps, and a tab with no place
    /// from before the first stop.</summary>
    public Guid? Swipe(Guid shownTabId, AdjacentDirection direction, IReadOnlyList<FolderState> folders,
        Func<TabPlacement, bool> isSectionExpanded) {
        ArgumentNullException.ThrowIfNull(direction);
        var stops = Stops(folders, isSectionExpanded);
        int shown = -1;
        int card = -1;
        for (int index = 0; index < stops.Count && shown < 0; index++) {
            for (int member = 0; member < stops[index].Members.Count && card < 0; member++)
                if (stops[index].Members[member] == shownTabId) card = member;
            if (card >= 0) shown = index;
        }
        int? reached;
        if (shown >= 0) {
            var members = stops[shown].Members;
            if (direction.Within(card, members.Count) is { } next) return members[next];
            reached = direction.Within(shown, stops.Count);
        } else {
            var positions = Positions();
            int gap = positions.TryGetValue(shownTabId, out int place) ? stops.Count(stop => positions[stop.Members[0]] < place) : 0;
            reached = direction.WithinFromGap(gap, stops.Count);
        }
        return reached is { } stop ? direction.Entering(stops[stop].Members) : null;
    }

    private static HashSet<Guid> Collapsed(IReadOnlyList<FolderState> folders) =>
        folders.Where(folder => folder.IsCollapsed).Select(folder => folder.Id).ToHashSet();

    private IEnumerable<Guid> Walk(Func<TabPlacement, bool> isSectionExpanded, Func<Guid, bool> isFolderExpanded) =>
        Rows(isSectionExpanded, isFolderExpanded).SelectMany(row => row.Listed);

    /// Every row of the sections `isSectionExpanded` answers for, in order, each
    /// folder row followed by its inside when `isFolderExpanded` answers for it.
    private IEnumerable<SidebarRow> Rows(Func<TabPlacement, bool> isSectionExpanded, Func<Guid, bool> isFolderExpanded) {
        var insides = new Dictionary<Guid, SidebarList>();
        foreach (var list in Lists)
            if (list.FolderId is { } id) insides.TryAdd(id, list);
        IEnumerable<SidebarRow> List(IReadOnlyList<SidebarRow> rows) {
            foreach (var row in rows) {
                yield return row;
                if (row.Kind.OpensList && isFolderExpanded(row.Id) && insides.TryGetValue(row.Id, out var inside))
                    foreach (var nested in List(inside.Rows)) yield return nested;
            }
        }
        return Lists.Where(list => list.FolderId is null && isSectionExpanded(list.Section)).SelectMany(list => List(list.Rows));
    }

    #endregion

    #region Actions - Changes

    /// <summary>Whether two versions of a Space's tabs and folders list the same outline,
    /// read without building either: the same tabs and folders in the same order, each
    /// with the same place, folder, split and Start Page state, and each folder with the
    /// same section, parent and anchor. A new title, address or icon lists the same.</summary>
    public static bool ListsAlike(IReadOnlyList<TabState> tabs, IReadOnlyList<TabState> otherTabs, IReadOnlyList<FolderState> folders,
        IReadOnlyList<FolderState> otherFolders) {
        ArgumentNullException.ThrowIfNull(tabs);
        ArgumentNullException.ThrowIfNull(otherTabs);
        ArgumentNullException.ThrowIfNull(folders);
        ArgumentNullException.ThrowIfNull(otherFolders);
        if (ReferenceEquals(tabs, otherTabs) && ReferenceEquals(folders, otherFolders)) return true;
        if (tabs.Count != otherTabs.Count || folders.Count != otherFolders.Count) return false;
        for (int index = 0; index < tabs.Count; index++) {
            var tab = tabs[index];
            var other = otherTabs[index];
            if (ReferenceEquals(tab, other)) continue;
            if (tab.Id != other.Id || tab.Placement != other.Placement || tab.FolderId != other.FolderId
                || tab.SplitGroupId != other.SplitGroupId || tab.IsStartPage != other.IsStartPage) return false;
        }
        for (int index = 0; index < folders.Count; index++) {
            var folder = folders[index];
            var other = otherFolders[index];
            if (ReferenceEquals(folder, other)) continue;
            if (folder.Id != other.Id || folder.Location != other.Location || folder.ParentId != other.ParentId
                || folder.OrderAnchorTabId != other.OrderAnchorTabId) return false;
        }
        return true;
    }

    /// <summary>The lists of this outline that <paramref name="previous"/> lacks or holds
    /// otherwise, and the folders whose lists this outline no longer has.</summary>
    public (IReadOnlyList<SidebarList> Changed, IReadOnlyList<Guid> RemovedFolderIds) Since(SidebarOutline previous) {
        ArgumentNullException.ThrowIfNull(previous);
        var sections = new Dictionary<TabPlacement, SidebarList>();
        var folders = new Dictionary<Guid, SidebarList>();
        foreach (var list in previous.Lists) {
            if (list.FolderId is { } id) folders.TryAdd(id, list);
            else sections.TryAdd(list.Section, list);
        }
        var changed = new List<SidebarList>();
        var kept = new HashSet<Guid>();
        foreach (var list in Lists) {
            SidebarList? was;
            if (list.FolderId is { } id) {
                kept.Add(id);
                was = folders.GetValueOrDefault(id);
            } else {
                was = sections.GetValueOrDefault(list.Section);
            }
            if (was is null || !was.Equals(list)) changed.Add(list);
        }
        return ([.. changed], [.. folders.Keys.Where(id => !kept.Contains(id))]);
    }

    #endregion

    #region Actions - Equality

    public bool Equals(SidebarOutline? other) => other is not null && Lists.SequenceEqual(other.Lists);

    public override int GetHashCode() => Lists.Count;

    #endregion
}
