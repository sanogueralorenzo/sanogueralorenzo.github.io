using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One import into a session: the Spaces it brings, read from the stored
/// format, and the session's own Spaces while the import edits them. Each
/// import intent runs its own rules over them, then `Finish` gives every
/// record the identity sync needs and says where each tab came from. Image
/// bytes never reach the core: the platform matches each imported tab to the
/// image it holds by the tab it came from.
internal sealed class NativeWorkspaceImport {
    #region Static Variables

    /// The most folders an import leaves a Space holding.
    internal const int MaximumFolders = 500;

    /// The saved folder that receives imported pinned tabs past the limit.
    internal const string OverflowFolderTitle = "Imported Pinned Tabs";
    internal const string OverflowFolderSymbol = "pin.slash";

    /// The fewest tabs a split brings.
    private const int MinimumSplitMembers = 2;

    /// How deep an imported Space may nest, as the stored format reads it.
    private static readonly JsonDocumentOptions SpacesDocument = new() { MaxDepth = 64 };

    #endregion

    #region Types

    /// Where a tab or archive record came from: `Source` is the position of
    /// the imported Space among the import's Spaces, or null for the
    /// session's own tab, and `TabId` the identity it had there.
    private sealed record Origin(int? Source, Guid TabId);

    /// A Space while the import edits it. Spaces are compared by this holder, so a
    /// Space keeps its place in the import as its record is replaced.
    private sealed class Draft(SpaceState state, bool isOriginal) {
        public SpaceState State { get; set; } = state;
        /// The record the session held for its own Space, or null for a Space
        /// the import brings.
        public SpaceState? Original { get; } = isOriginal ? state : null;
        public bool IsOriginal => Original is not null;
        /// Whether the import changed the session's own Space: gave it tabs or
        /// folders, or another name or look.
        public bool IsChanged => Original is { } original && !State.Equals(original);
        public Guid Id => State.Id;

        // The tab this Space should show first. It is a hint for the window that
        // ran the import, never a stored selection.
        public Guid? ShownTab { get; set; }
    }

    /// The session an import leaves, the tabs it placed from its Spaces and the
    /// session's own tabs that took a new identity.
    internal sealed record Result(SessionState Session, IReadOnlyList<ImportedTab> Imported, IReadOnlyList<SessionTabCopy> Copied);

    #endregion

    #region Variables

    private readonly SessionState session;
    /// The session's Spaces, then those the import adds, in the order the
    /// session will hold them.
    private List<Draft> spaces;
    /// The import's Spaces, in the order it brings them.
    private readonly IReadOnlyList<Draft> inputs;
    private readonly Dictionary<Draft, HashSet<Guid>> originalFolderIds;
    private readonly Dictionary<Draft, HashSet<Guid>> originalHistoryIds;
    // Tab and archive records by reference, so two records that share an identity
    // keep their own origins.
    private readonly Dictionary<object, Origin> origins = new(ReferenceEqualityComparer.Instance);
    /// The tabs a reviewed import of another browser brings, by where they
    /// came from, which the import counts as used.
    private readonly HashSet<Origin> reviewed = [];
    private Guid? defaultSpace;
    private Guid? seedMarker;
    /// The first Space the import brought or changed, which the window shows.
    private Draft? affected;

    /// The session's own Spaces the import changes, as the session holds them:
    /// each it gives tabs or folders, or another name or look. Moving a Space in
    /// the order changes no Space, as `ReorderSpaces` moves a locked one too,
    /// and neither does replacing a first launch's disposable Spaces, which
    /// removes them as a deletion removes a locked Space.
    internal IReadOnlyList<SpaceState> Changed => [.. spaces.Where(space => space.IsChanged).Select(space => space.Original!)];

    #endregion

    #region Constructors

    /// Takes `spaces`, the imported Spaces, against `session`. Throws
    /// `Rejected` with `InvalidImport` for Spaces that hold a split repair
    /// would rewrite.
    internal NativeWorkspaceImport(SessionState session, IReadOnlyList<SpaceState> spaces) {
        this.session = session;
        defaultSpace = session.DefaultSpaceId;
        seedMarker = session.DisposableSeedMarker;
        this.spaces = [.. session.Spaces.Select(space => new Draft(space, isOriginal: true))];
        foreach (var space in this.spaces) Track(space.State, source: null);
        originalFolderIds = this.spaces.ToDictionary(space => space, space => space.State.Folders.Select(f => f.Id).ToHashSet());
        originalHistoryIds = this.spaces.ToDictionary(space => space, space => space.State.History.Select(h => h.Id).ToHashSet());
        inputs = [.. spaces.Select(space => new Draft(space, isOriginal: false))];
        for (int index = 0; index < inputs.Count; index++) Track(inputs[index].State, index);
        foreach (var input in inputs)
            SplitMember.RequireWellFormed(
                [.. input.State.Tabs.Select(t => new SplitMember(t.SplitGroupId, t.Placement, t.FolderId))]);
    }

    #endregion

    #region Actions - Reading

    /// The imported Spaces, as the stored format spells them in a JSON array.
    /// Throws `Rejected` with `InvalidImport` for Spaces that do not decode.
    internal static IReadOnlyList<SpaceState> Decoded(byte[] spaces) {
        try {
            return [.. JsonNode.Parse(spaces, documentOptions: SpacesDocument)!.AsArray().Select(StoredSessionCodec.DecodeSpace)];
        } catch (Exception error) when (StoredSession.IsUndecodable(error)) {
            throw new Rejected(new InvalidImport(ImportFlaw.Unreadable));
        }
    }

    private void Track(SpaceState space, int? source) {
        foreach (var tab in space.Tabs) origins[tab] = new(source, tab.Id);
        foreach (var archived in space.ArchivedTabs) origins[archived] = new(source, archived.Tab.Id);
    }

    /// A changed copy of a tab keeps the tab's origin.
    private TabState Copied(TabState tab, TabState copy) {
        if (origins.TryGetValue(tab, out var origin)) origins[copy] = origin;
        return copy;
    }

    /// Each choice with the imported Space it names, in the choices' order.
    /// Throws `Rejected` with `InvalidImport` unless they name each imported
    /// Space exactly once.
    private IReadOnlyList<(Draft Input, TChoice Choice)> Pair<TChoice>(IReadOnlyList<TChoice> choices, Func<TChoice, Guid> named) {
        var paired = Paired(inputs, choices, input => input.Id, named);
        var byChoice = paired.ToDictionary(pair => named(pair.Choice), pair => pair.Source);
        return [.. choices.Select(choice => (byChoice[named(choice)], choice))];
    }

    /// Each source with the one choice that names it, in the sources' order.
    /// Throws `Rejected` with `InvalidImport` unless the choices name each
    /// source exactly once and the sources' identities are distinct.
    private static IReadOnlyList<(TSource Source, TChoice Choice)> Paired<TSource, TChoice>(IReadOnlyList<TSource> sources,
        IReadOnlyList<TChoice> choices, Func<TSource, Guid> sourceId, Func<TChoice, Guid> choiceId) {
        var byId = new Dictionary<Guid, TChoice>();
        foreach (var choice in choices)
            if (!byId.TryAdd(choiceId(choice), choice)) throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices));
        if (sources.Select(sourceId).Distinct().Count() != sources.Count || byId.Count != sources.Count)
            throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices));
        return [.. sources.Select(source => byId.TryGetValue(sourceId(source), out var choice)
            ? (source, choice) : throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices)))];
    }

    #endregion

    #region Actions - Imports

    /// A file's Spaces join after the session's own, each showing its first
    /// tab. A first launch's disposable Spaces never count against the limit:
    /// they stay while the file's Spaces fit beside them, and otherwise make
    /// way for them, as they do for a reviewed import. Throws `Rejected` with
    /// `SpaceLimitReached` when the file's Spaces do not fit, and
    /// `SpaceBeingDeleted` when disposable Spaces must make way while one is
    /// going away.
    internal void AddSpaces() {
        bool replaceSeed = seedMarker is not null && (long)spaces.Count + inputs.Count > SessionState.MaximumSpaces;
        SessionState.RequireSpaceCapacity(replaceSeed ? 0 : spaces.Count, inputs.Count);
        if (replaceSeed) {
            ReplaceSeed();
            seedMarker = null;
        }
        foreach (var input in inputs) {
            if (input.State.Tabs.FirstOrDefault() is { } first) input.ShownTab = first.Id;
            spaces.Add(input);
        }
        affected = inputs.FirstOrDefault();
    }

    /// The Space a manual setup's `space` brings into the import: the new
    /// Space it makes, holding nothing yet, or the identity and profile of the
    /// existing Space it names. `ApplySetup` gives it its name and look.
    internal static SpaceState SetupSpace(SetupDraftSpace space) {
        ArgumentNullException.ThrowIfNull(space);
        var customization = space.Customization;
        var settings = new SpaceSettings(customization.Name, customization.Symbol, customization.Accent, customization.Branding,
            StoredSessionCodec.DefaultBrowsingPreferences, StoredSessionCodec.DefaultCredentialPreferences, SpaceAccessPolicy.Open,
            IsSavedTabsExpanded: true, SavedTabsExpansionModifiedAt: null);
        return new(space.SpaceId, space.ProfileId, settings, Folders: [], Tabs: [], SplitGroups: [], ArchivedTabs: [], History: []);
    }

    /// Applies a manual setup's Spaces in their order; see `ApplyManualSetup`.
    internal void ApplySetup(SetupDraft setup) {
        var paired = Pair(setup.Spaces, draft => draft.SpaceId);
        SessionState.RequireSpaceCapacity(spaces.Count, setup.Spaces.Count(draft => draft.IsNew));
        foreach (var (input, draft) in paired) {
            var id = input.Id;
            bool created = draft.IsNew;
            var destination = created ? input : spaces.FirstOrDefault(s => s.Id == id);
            if (destination is null) continue; // A setup cannot recreate an existing Space deleted elsewhere.
            Available(id);
            if (!created && destination.State.ProfileId != input.State.ProfileId) throw new Rejected(new SpaceProfileChanged(id));
            if (created && spaces.Any(s => s.Id == id)) throw new Rejected(new SpaceAlreadyExists(id));
            if (created && spaces.Any(s => s.State.ProfileId == input.State.ProfileId))
                throw new Rejected(new ProfileInUse(input.State.ProfileId));
            Customize(destination, draft.Customization);
            if (!created) continue;
            spaces.Add(destination);
            affected ??= destination;
        }
        if (setup.OrderWasEdited) {
            var order = paired.Select(pair => pair.Input.Id).ToArray();
            spaces = [.. order.Select(id => spaces.FirstOrDefault(s => s.Id == id)).OfType<Draft>()
                .Concat(spaces.Where(s => !order.Contains(s.Id)))];
        }
        seedMarker = null;
    }

    /// Imports the reviewed Spaces the review includes, in their order; see
    /// `ImportReviewedSpaces`. New identities come from `ids`.
    internal void ImportReviewed(IReadOnlyList<SetupReviewSpace> reviews, IIdSource ids) {
        var included = Pair(reviews, review => review.Source.Id).Where(pair => pair.Choice.Included).ToArray();
        if (included.Length == 0) throw new Rejected(new NoIncludedSpaces());
        bool replaceSeed = seedMarker is not null;
        SessionState.RequireSpaceCapacity(replaceSeed ? 0 : spaces.Count,
            included.Count(pair => pair.Choice.DestinationId is null));
        if (replaceSeed) ReplaceSeed();
        foreach (var (input, review) in included) {
            var destination = review.DestinationId is { } destinationId ? spaces.FirstOrDefault(s => s.Id == destinationId) : input;
            if (destination is null) continue;
            Available(destination.Id);
            Customize(destination, review.Customization);
            Import(review, input, destination, isNew: review.DestinationId is null, ids);
            if (review.DestinationId is null) spaces.Add(destination);
            affected ??= destination;
        }
        if (affected is not null) seedMarker = null;
    }

    /// Removes a first launch's disposable Spaces, which an import takes the
    /// place of. Throws `Rejected` with `SpaceBeingDeleted` while one is going
    /// away.
    private void ReplaceSeed() {
        if (session.SpaceDeletions.Count > 0) throw new Rejected(new SpaceBeingDeleted(session.SpaceDeletions[0].SpaceId));
        spaces.Clear();
        defaultSpace = null;
    }

    #endregion

    #region Actions - Reviewed tabs

    /// A reviewed Space's included tabs, in the placements the review chose, with
    /// the folders they need where they stay in a folder's place, saved tabs or
    /// a tab group's open tabs, and the splits whose tabs still come together.
    /// Pinned tabs past the limit become saved tabs in the overflow folder. New
    /// identities come from `ids`.
    private void Import(SetupReviewSpace review, Draft input, Draft destination, bool isNew, IIdSource ids) {
        var included = review.IncludedTabIds.ToHashSet();
        var overrides = review.Placements.GroupBy(choice => choice.TabId).ToDictionary(group => group.Key, group => group.Last().Placement);
        TabPlacement PlacementFor(TabState tab) => overrides.GetValueOrDefault(tab.Id, tab.Placement);
        var additions = Fitting([.. input.State.Tabs.Where(t => included.Contains(t.Id))], PlacementFor,
            BrowserTabCollection.MaximumTabs - (isNew ? 0 : destination.State.Tabs.Count));
        var sourceFolders = input.State.Folders;
        var folders = isNew ? [] : destination.State.Folders.ToList();
        var byId = sourceFolders.GroupBy(f => f.Id).ToDictionary(g => g.Key, g => g.First());
        // A tab keeps its folder while it stays in the folder's place.
        bool Kept(TabState tab) => tab.FolderId is { } id && byId.TryGetValue(id, out var held) && held.Location == PlacementFor(tab)
            && held.Location.HoldsFolders;
        var required = additions.Where(Kept).Select(t => t.FolderId!.Value).ToHashSet();
        var pending = new Stack<Guid>(required);
        while (pending.TryPop(out var id))
            if (byId.TryGetValue(id, out var f) && f.ParentId is { } parent && required.Add(parent)) pending.Push(parent);
        Dictionary<Guid, Guid> mapping = [];
        foreach (var folder in FolderTree.RepairPreorder(sourceFolders).Where(f => required.Contains(f.Id))) {
            var original = byId[folder.Id];
            Guid? parent = folder.ParentId is { } p && mapping.TryGetValue(p, out var mapped) ? mapped : null;
            var match = folders.FirstOrDefault(f => f.ParentId == parent && f.Location == original.Location
                && FolderState.MatchKey(f.Title) == FolderState.MatchKey(original.Title));
            if (match is not null) { mapping[folder.Id] = match.Id; continue; }
            if (folders.Count >= MaximumFolders) continue;
            var identity = folder.Id;
            while (folders.Any(f => f.Id == identity)) identity = ids.Next();
            folders.Add(original with {
                Id = identity,
                ParentId = parent,
                IsCollapsed = false,
                CollapseModifiedAt = null,
                OrderAnchorTabId = null
            });
            mapping[folder.Id] = identity;
        }
        var counts = (isNew ? [] : destination.State.Tabs).CountBy(tab => tab.Placement).ToDictionary();
        var overflowFolder = folders.FirstOrDefault(f =>
            string.Equals(f.Title, OverflowFolderTitle, StringComparison.OrdinalIgnoreCase));
        var edited = additions.Select(tab => {
            var placement = PlacementFor(tab);
            Guid? folder;
            counts[placement] = counts.GetValueOrDefault(placement) + 1;
            if (placement.Fitting(counts[placement]) is var spill && spill != placement) {
                placement = spill;
                if (overflowFolder is null && folders.Count < MaximumFolders) {
                    overflowFolder = new FolderState(ids.Next(), spill, OverflowFolderTitle,
                        OverflowFolderSymbol);
                    folders.Add(overflowFolder);
                }
                folder = overflowFolder?.Id;
            } else folder = Kept(tab) && tab.FolderId is { } old && mapping.TryGetValue(old, out var copied)
                  ? copied : null;
            return Copied(tab, tab with {
                Placement = placement,
                FolderId = folder,
                SavedUrl = placement.IsDurable ? tab.SavedUrl ?? tab.Url : null,
                Symbol = placement.ImportedSymbol ?? tab.Symbol
            });
        }).ToArray();
        var existing = isNew ? [] : destination.State.Tabs;
        foreach (var tab in edited)
            if (origins.TryGetValue(tab, out var origin)) reviewed.Add(origin);
        var (split, splits) = Split(input, destination, isNew, existing, edited, ids);
        destination.State = destination.State with { Folders = [.. folders], Tabs = [.. existing, .. split], SplitGroups = splits };
        // A new Space shows its first imported tab.
        if (isNew && edited.FirstOrDefault() is { } first) destination.ShownTab = first.Id;
    }

    /// As many of `tabs` as `room` holds, in their order, the pinned and open
    /// ones first, then the saved ones in order, so a Space joining another
    /// never holds more tabs than a Space keeps.
    private static TabState[] Fitting(TabState[] tabs, Func<TabState, TabPlacement> placement, int room) {
        if (tabs.Length <= room) return tabs;
        var kept = tabs.Select((tab, index) => (Tab: tab, Index: index)).OrderBy(entry => placement(entry.Tab) == TabPlacement.Saved ? 1 : 0)
            .Take(Math.Max(0, room)).Select(entry => entry.Index).ToHashSet();
        return [.. tabs.Where((_, index) => kept.Contains(index))];
    }

    /// `edited`, the tabs a reviewed Space brings after `existing`, each in the
    /// split it came in where that split still holds together beside the
    /// destination's tabs, and the destination's splits with those it brings.
    /// A split that no longer holds, because the review left out or moved one
    /// of its tabs, leaves its tabs on their own.
    private (TabState[] Tabs, IReadOnlyList<SplitGroupState> Splits) Split(Draft input, Draft destination, bool isNew,
        IReadOnlyList<TabState> existing, TabState[] edited, IIdSource ids) {
        var held = isNew ? [] : destination.State.SplitGroups.ToList();
        var sources = input.State.SplitGroups.GroupBy(split => split.Id).ToDictionary(group => group.Key, group => group.First());
        Dictionary<Guid, Guid> identities = [];
        Guid? Mapped(Guid? id) {
            if (id is not { } source || !sources.ContainsKey(source)) return null;
            if (identities.TryGetValue(source, out var mapped)) return mapped;
            var identity = source;
            while (held.Any(split => split.Id == identity) || identities.ContainsValue(identity)) identity = ids.Next();
            return identities[source] = identity;
        }
        var asked = edited.Select(tab => Mapped(tab.SplitGroupId)).ToArray();
        var all = existing.Select(tab => new SplitMember(tab.SplitGroupId, tab.Placement, tab.FolderId))
            .Concat(edited.Select((tab, index) => new SplitMember(asked[index], tab.Placement, tab.FolderId))).ToArray();
        var repaired = SplitMember.Repair(all).Skip(existing.Count).ToArray();
        var counts = repaired.OfType<Guid>().GroupBy(id => id).ToDictionary(group => group.Key, group => group.Count());
        var tabs = edited.Select((tab, index) => {
            Guid? kept = repaired[index] is { } joined && joined == asked[index] && counts[joined] >= MinimumSplitMembers ? joined : null;
            return tab.SplitGroupId == kept ? tab : Copied(tab, tab with { SplitGroupId = kept });
        }).ToArray();
        foreach (var (source, identity) in identities)
            if (tabs.Any(tab => tab.SplitGroupId == identity)) held.Add(sources[source] with { Id = identity });
        return (tabs, held);
    }

    #endregion

    #region Actions - Identities

    /// The session the import leaves, stamped `now`: every folder and history
    /// record keeps an identity no other Space holds, repair gives each Space,
    /// profile and tab its own, and `followUp` shows the first Space the import
    /// brought or changed and the tab each Space it touched shows first. New
    /// identities come from `ids`, in the order the records are met.
    internal Result Finish(DateTimeOffset now, IIdSource ids, WindowFollowUp followUp) {
        // Folder and history record IDs are global in sync, even though their
        // native collections are nested under Spaces. Reserve existing IDs first
        // so an imported Space placed earlier cannot steal another Space's records.
        var folderIds = originalFolderIds.Values.SelectMany(set => set).ToHashSet();
        var historyIds = originalHistoryIds.Values.SelectMany(set => set).ToHashSet();
        foreach (var space in spaces) Reserve(space, space.IsOriginal ? originalFolderIds[space] : null,
            space.IsOriginal ? originalHistoryIds[space] : null, folderIds, historyIds, ids);
        // A reviewed import counts as using the open tabs it brings, so cleanup
        // never archives them for how long ago the other browser last showed
        // them. A file of Crest's own keeps the times it saved.
        foreach (var space in spaces) space.State = space.State with {
            Tabs = [.. space.State.Tabs.Select(tab => origins.TryGetValue(tab, out var origin) && reviewed.Contains(origin)
                && !tab.Placement.IsDurable && tab.LastActivatedAt < now ? Copied(tab, tab with { LastActivatedAt = now }) : tab)]
        };
        int affectedIndex = affected is null ? -1 : spaces.IndexOf(affected);
        // Repair may replace colliding identities, so hints and origins travel by position.
        var shown = new List<(int Space, int Tab)>();
        for (int si = 0; si < spaces.Count; si++)
            if (spaces[si].ShownTab is { } tab && spaces[si].State.Tabs.Select(t => t.Id).ToList().IndexOf(tab) is var ti and >= 0)
                shown.Add((si, ti));
        var before = spaces.Select(space => space.State).ToArray();
        var imported = session with {
            Spaces = before,
            DefaultSpaceId = defaultSpace,
            DisposableSeedMarker = seedMarker
        };
        var repaired = NativeSessionMaintenance.Repair(imported, now, null, ids, out _);
        // Show the imported instance even when repair replaced a colliding ID.
        if (affectedIndex >= 0) followUp.ShowSpace(repaired.Spaces[affectedIndex].Id);
        foreach (var (si, ti) in shown) followUp.ShowTab(repaired.Spaces[si].Id, repaired.Spaces[si].Tabs[ti].Id);
        var (importedTabs, copies) = Placed(before, repaired);
        return new(repaired, importedTabs, copies);
    }

    /// Where each tab of `repaired` came from, matched by position with the
    /// records `before` held: each tab an imported Space brought, and each of
    /// the session's own tabs repair gave a new identity. A Space repair kept
    /// as it was, such as one being deleted, placed nothing.
    private (IReadOnlyList<ImportedTab> Imported, IReadOnlyList<SessionTabCopy> Copied) Placed(IReadOnlyList<SpaceState> before,
        SessionState repaired) {
        var imported = new List<ImportedTab>();
        var copied = new List<SessionTabCopy>();
        void Place(object record, Guid id) {
            if (!origins.TryGetValue(record, out var origin)) return;
            if (origin.Source is { } source) imported.Add(new(id, source, origin.TabId));
            else if (id != origin.TabId) copied.Add(new(origin.TabId, id));
        }
        for (int si = 0; si < before.Count; si++) {
            var space = repaired.Spaces[si];
            if (ReferenceEquals(space, before[si])) continue;
            for (int ti = 0; ti < before[si].Tabs.Count; ti++) Place(before[si].Tabs[ti], space.Tabs[ti].Id);
            // Repair drops a Start Page from the archive.
            var archive = before[si].ArchivedTabs
                .Where(archived => archived.Tab.Url is not null || archived.Tab.NativeContent is not null).ToArray();
            for (int ti = 0; ti < archive.Length; ti++) Place(archive[ti], space.ArchivedTabs[ti].Tab.Id);
        }
        return (imported, copied);
    }

    /// Gives a Space's folders and history identities no other Space holds,
    /// keeping the ones it had before the import, and points its folder
    /// references at the new folder identities.
    private void Reserve(Draft space, HashSet<Guid>? originalFolders, HashSet<Guid>? originalHistory,
        HashSet<Guid> folderIds, HashSet<Guid> historyIds, IIdSource ids) {
        Dictionary<Guid, Guid> mapping = [];
        var folders = space.State.Folders.Select(folder => {
            var id = folder.Id;
            if (originalFolders?.Contains(folder.Id) != true)
                while (!folderIds.Add(id)) id = ids.Next();
            mapping.TryAdd(folder.Id, id);
            return folder with { Id = id };
        }).ToArray();
        Guid? Mapped(Guid? id) => id is { } value && mapping.TryGetValue(value, out var mapped) ? mapped : id;
        var history = space.State.History.Select(entry => {
            var id = entry.Id;
            if (originalHistory?.Contains(entry.Id) != true)
                while (!historyIds.Add(id)) id = ids.Next();
            return entry with { Id = id };
        }).ToArray();
        space.State = space.State with {
            Folders = [.. folders.Select(folder => folder with { ParentId = Mapped(folder.ParentId) })],
            Tabs = [.. space.State.Tabs.Select(tab => tab.FolderId == Mapped(tab.FolderId) ? tab
                : Copied(tab, tab with { FolderId = Mapped(tab.FolderId) }))],
            History = [.. history]
        };
    }

    #endregion

    #region Actions - Rules

    /// Gives `space` the name and look `customization` chooses. The session's
    /// own Space keeps its settings when the choice reads as the name and look
    /// it already has, so a draft left as it was changes nothing.
    private static void Customize(Draft space, SpaceCustomization customization) {
        var settings = space.State.Settings;
        var chosen = Customized(settings, customization);
        if (space.IsOriginal && settings.Branding is { } branding
            && chosen == Customized(settings, new(settings.Name, settings.Symbol, settings.Accent, branding))) return;
        space.State = space.State with { Settings = chosen };
    }

    /// `settings` with the name and look `customization` chooses, as the core
    /// keeps them.
    private static SpaceSettings Customized(SpaceSettings settings, SpaceCustomization customization) => settings with {
        Name = SpaceCustomization.Resolved(customization.Name),
        Symbol = SpaceCustomization.ResolvedSymbol(customization.Symbol),
        Accent = customization.Accent,
        Branding = SpaceBranding.Normalized(customization.Branding)
    };

    /// Throws `Rejected` with `SpaceBeingDeleted` when `id` is going away.
    private void Available(Guid id) {
        if (session.PendingDeletion(id) is not null) throw new Rejected(new SpaceBeingDeleted(id));
    }

    #endregion
}
