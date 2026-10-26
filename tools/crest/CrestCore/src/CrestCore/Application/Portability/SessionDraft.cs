using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One window or Space another browser's session holds, as its reader found
/// it: the folders and tabs, with the folder identities the browser spells,
/// and the name, symbol, accent and look it gave the Space, where it gave
/// any. `Ordinal` counts the browser's windows or Spaces from one. A browser
/// that keeps a profile for each Space, as Arc does, names the folder of the
/// Space's own profile, `Profile`, when it is not the browser's first.
internal sealed record SessionDraft(int Ordinal, string? Name, IReadOnlyList<SessionFolder> Folders, IReadOnlyList<SessionTab> Tabs,
    string? Symbol = null, SpaceAccent? Accent = null, SpaceBranding? Branding = null, string? Profile = null) {
    #region Static Variables

    /// The most tabs one window or Space brings.
    public const int MaximumTabs = BrowserDataSpace.MaximumTabs;

    private const string UntitledFolder = "Untitled Folder";
    /// The fewest tabs a split view shows.
    private const int MinimumSplitMembers = 2;

    #endregion

    #region Actions - Spaces

    /// The Spaces `drafts` make for `source`, a browser that names its own
    /// Spaces: each draft that holds a tab or a name, in order, named as the
    /// browser named it or else by `names`, with every record a new identity
    /// from `ids`. A tab with no usable time is dated `importedAt`. At most
    /// `room` Spaces come, each with the draft it came from; a draft past
    /// them, holding more than a Space keeps or naming a folder twice or out
    /// of place is left out in `leftOut`, with why.
    public static IReadOnlyList<(SpaceState Space, SessionDraft Draft)> Spaces(IReadOnlyList<SessionDraft> drafts, ImportSource source,
        ImportSpaceNames names, IIdSource ids, DateTimeOffset importedAt, int room, ICollection<ImportLeftOut> leftOut) {
        ArgumentNullException.ThrowIfNull(leftOut);
        var kept = drafts.Where(draft => draft.Tabs.Count > 0 || draft.Name is not null).ToArray();
        bool numbered = kept.Length > 1;
        List<(SpaceState, SessionDraft)> made = [];
        foreach (var draft in kept) {
            if (made.Count >= room) {
                leftOut.Add(new(draft.ShownName(names, numbered), new SessionOverLimits()));
                continue;
            }
            try {
                made.Add((draft.Space(source, names, numbered, ids, importedAt), draft));
            } catch (Rejected rejected) {
                leftOut.Add(new(draft.ShownName(names, numbered), rejected.Rejection));
            }
        }
        return made;
    }

    /// One Space holding the tabs of a profile's windows, `drafts`: the first
    /// window that holds a tab, joined by each later one that fits beside it,
    /// each made as `Spaces` makes them. Null when no window holds a tab. A
    /// window a Space would not keep or that does not fit is skipped, and
    /// `problem` says why the last one was.
    public static SpaceState? Merged(IReadOnlyList<SessionDraft> drafts, ImportSource source, ImportSpaceNames names, IIdSource ids,
        DateTimeOffset importedAt, out Rejection? problem) {
        problem = null;
        var kept = drafts.Where(draft => draft.Tabs.Count > 0).ToArray();
        SpaceState? merged = null;
        foreach (var draft in kept) {
            if (merged is not null && merged.Tabs.Count + draft.Tabs.Count > MaximumTabs) {
                problem = new SessionOverLimits();
                continue;
            }
            SpaceState window;
            try {
                window = draft.Space(source, names, numbered: kept.Length > 1, ids, importedAt);
            } catch (Rejected rejected) {
                problem = rejected.Rejection;
                continue;
            }
            if (merged is null) {
                merged = window;
            } else if (merged.Folders.Count + window.Folders.Count > FolderTree.MaximumCount) {
                problem = new SessionOverLimits();
            } else {
                merged = merged with { Folders = [.. merged.Folders, .. window.Folders], Tabs = [.. merged.Tabs, .. window.Tabs] };
            }
        }
        return merged;
    }

    /// The Space this draft makes. Throws `Rejected` with `SessionOverLimits`
    /// when it holds more than a Space keeps, and `SessionUnrecognized` for a
    /// folder it names twice or cannot place.
    private SpaceState Space(ImportSource source, ImportSpaceNames names, bool numbered, IIdSource ids, DateTimeOffset importedAt) {
        if (Tabs.Count > MaximumTabs) throw new Rejected(new SessionOverLimits());
        var portable = Portable(source, names, numbered, ids, importedAt);
        try {
            return portable.Materialize(ids, importedAt);
        } catch (Rejected rejected) when (rejected.Rejection is ArchiveInvalid) {
            throw new Rejected(new SessionOverLimits());
        }
    }

    /// The name the Space shows: the browser's, or else its name from
    /// `names`, numbered by its place when the browser brings several.
    private string ShownName(ImportSpaceNames names, bool numbered) => ImportText.Title(Name, Fallback(names, numbered));

    private string Fallback(ImportSpaceNames names, bool numbered) => numbered
        ? names.NumberedSpaceName.Replace("%lld", Ordinal.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal)
        : names.SpaceName;

    /// The Space as a Crest browser-data file would keep it. Pinned tabs past
    /// the limit become saved tabs in an `Imported Pinned Tabs` folder, or
    /// outside any folder when the Space holds as many as it keeps.
    private BrowserDataSpace Portable(ImportSource source, ImportSpaceNames names, bool numbered, IIdSource ids,
        DateTimeOffset importedAt) {
        if (Folders.Count > FolderTree.MaximumCount) throw new Rejected(new SessionOverLimits());
        Dictionary<string, Guid> folderIds = new(StringComparer.Ordinal);
        foreach (var folder in Folders)
            if (!folderIds.TryAdd(folder.SourceId, ids.Next())) throw new Rejected(new SessionUnrecognized());
        List<BrowserDataFolder> folders = [.. Folders.Select(folder => {
            Guid? parent = null;
            if (folder.ParentSourceId is { } parentSource)
                parent = parentSource != folder.SourceId && folderIds.TryGetValue(parentSource, out var mapped) ? mapped
                    : throw new Rejected(new SessionUnrecognized());
            string title = ImportText.Bounded(folder.Title, UntitledFolder, ImportText.MaximumFolderTitle)
                ?? throw new Rejected(new SessionOverLimits());
            return Folder(folderIds[folder.SourceId], title, FolderState.DefaultSymbol, parent, folder.Placement, folder.Color?.Color);
        })];
        var folderPlaces = folders.ToDictionary(folder => folder.Id, folder => folder.Location);
        if (!IsForest(folders)) throw new Rejected(new SessionOverLimits());

        var counts = new Dictionary<TabPlacement, int>();
        Guid? overflow = null;
        List<BrowserDataTab> tabs = [];
        var ordered = Gathered(Tabs);
        foreach (var tab in ordered) {
            var placement = tab.Placement;
            Guid? folder = tab.FolderSourceId is { } folderSource && folderIds.TryGetValue(folderSource, out var mapped) ? mapped : null;
            if (placement == TabPlacement.Saved && tab.FolderSourceId is not null && folder is null)
                throw new Rejected(new SessionUnrecognized());
            counts[placement] = counts.GetValueOrDefault(placement) + 1;
            if (placement.Fitting(counts[placement]) is var spill && spill != placement) {
                placement = spill;
                if (overflow is null && folders.Count < FolderTree.MaximumCount) {
                    overflow = ids.Next();
                    folders.Add(Folder(overflow.Value, NativeWorkspaceImport.OverflowFolderTitle, NativeWorkspaceImport.OverflowFolderSymbol,
                        parent: null, spill));
                    folderPlaces[overflow.Value] = spill;
                }
                folder = overflow;
            }
            string title = ImportText.Bounded(tab.Title, tab.Address.Host, ImportText.MaximumTitle)
                ?? throw new Rejected(new SessionOverLimits());
            string url = tab.Address.Spelling;
            bool fits = folder is { } held && folderPlaces.TryGetValue(held, out var place) && place == placement;
            tabs.Add(new(ids.Next(), title, NativeContent: null, url, placement.IsDurable ? url : null,
                placement.ImportedSymbol ?? TabIconMode.WebSymbol, placement,
                fits ? folder : null, SplitGroupId: null, tab.LastActivatedAt ?? importedAt));
        }
        var splits = Split(ordered, tabs, ids);

        string name = ImportText.Bounded(Name, Fallback(names, numbered), ImportText.MaximumSpaceName)
            ?? throw new Rejected(new SessionOverLimits());
        string symbol = Symbol ?? source.Symbol;
        return new(name, symbol, Accent ?? source.Accent, Branding ?? SpaceBranding.NeutralImport(symbol), Ordered(folders), tabs,
            splits, ArchivedTabs: [], History: [], StoredSessionCodec.DefaultBrowsingPreferences, SelectedTabId: null);
    }

    /// The split views of the browser's tabs that Crest keeps, joining their
    /// tabs in `tabs`: each whose tabs sit side by side, in one place and
    /// folder, at least two and no more than a split holds. The tabs of any
    /// other show on their own.
    private static List<BrowserDataSplit> Split(IReadOnlyList<SessionTab> sources, List<BrowserDataTab> tabs, IIdSource ids) {
        Dictionary<string, Guid> splitIds = new(StringComparer.Ordinal);
        Guid? Group(SessionTab tab) => tab.SplitSourceId is not { } source ? null
            : splitIds.TryGetValue(source, out var id) ? id : splitIds[source] = ids.Next();
        var asked = sources.Select(Group).ToArray();
        var kept = SplitMember.Repair([.. tabs.Select((tab, index) => new SplitMember(asked[index], tab.Placement, tab.FolderId))]);
        var counts = kept.OfType<Guid>().GroupBy(group => group).ToDictionary(group => group.Key, group => group.Count());
        List<BrowserDataSplit> splits = [];
        for (int index = 0; index < tabs.Count; index++) {
            Guid? group = kept[index] is { } joined && joined == asked[index] && counts[joined] >= MinimumSplitMembers ? joined : null;
            tabs[index] = tabs[index] with { SplitGroupId = group };
            if (group is { } made && splits.All(split => split.Id != made))
                splits.Add(new BrowserDataSplit(made, CustomTitle: null, TitleModifiedAt: null, CustomIconSymbol: null, IconModifiedAt: null,
                    Tint: null, TintModifiedAt: null));
        }
        return splits;
    }

    /// `tabs` in order, each split's tabs gathered beside its first, where the
    /// browser shows them together whatever their order in its file.
    private static IReadOnlyList<SessionTab> Gathered(IReadOnlyList<SessionTab> tabs) {
        List<SessionTab> ordered = new(tabs.Count);
        HashSet<string> placed = new(StringComparer.Ordinal);
        foreach (var tab in tabs) {
            if (tab.SplitSourceId is not { } split) {
                ordered.Add(tab);
            } else if (placed.Add(split)) {
                ordered.AddRange(tabs.Where(member => member.SplitSourceId == split));
            }
        }
        return ordered;
    }

    /// A folder in the default color, among the saved tabs unless `placement` says otherwise.
    private static BrowserDataFolder Folder(Guid id, string title, string symbol, Guid? parent, TabPlacement? placement = null,
        BrandColor? color = null) =>
        new(id, placement ?? TabPlacement.Saved, title, symbol, color ?? FolderState.DefaultColor, parent, IsCollapsed: false,
            OrderAnchorTabId: null);

    private static bool IsForest(IReadOnlyList<BrowserDataFolder> folders) {
        try {
            _ = new FolderTree([.. folders.Select(folder => folder.Materialize(folder.Id, folder.ParentId))]).DisplayOrder();
            return true;
        } catch (Exception error) when (error is BrowserRuleException or Rejected) {
            return false;
        }
    }

    /// `folders`, each parent before its children.
    private static IReadOnlyList<BrowserDataFolder> Ordered(IReadOnlyList<BrowserDataFolder> folders) {
        var order = new FolderTree([.. folders.Select(folder => folder.Materialize(folder.Id, folder.ParentId))]).DisplayOrder();
        var byId = folders.ToDictionary(folder => folder.Id);
        return [.. order.Select(folder => byId[folder.Id])];
    }

    #endregion
}
