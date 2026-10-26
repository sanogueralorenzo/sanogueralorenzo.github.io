using CrestCore.Application;

namespace CrestCore.Contracts;

/// Rules for reviewing an import before the workspace import applies it. An
/// imported Space joins the existing Space with the same name, tabs its
/// destination already holds are left out until the person asks for them,
/// pinned tabs past a destination's limit move to a saved folder, and no
/// choice brings more new Spaces than the workspace has room for. Each edit
/// answers the review as it leaves it, with what its choices mean against the
/// session worked out again.
public sealed partial record ImportReview {
    #region Actions - Starting

    internal static ImportReview Started(ImportSource source, IReadOnlyList<SpaceState> spaces,
        IReadOnlyList<ImportSpaceExtensions> extensions, IReadOnlyList<ImportLeftOut> leftOut,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(spaces);
        ArgumentNullException.ThrowIfNull(extensions);
        ArgumentNullException.ThrowIfNull(leftOut);
        ArgumentNullException.ThrowIfNull(session);
        var destinations = session.ImportDestinations;
        var offers = extensions.GroupBy(entry => entry.SpaceId).ToDictionary(group => group.Key,
            group => (IReadOnlyList<ImportExtension>)[.. group.SelectMany(entry => entry.Extensions)
                .DistinctBy(extension => extension.ExtensionId, StringComparer.Ordinal)]);
        int room = session.ImportRoom, created = 0;
        HashSet<Guid> joined = [];
        List<ImportReviewSpace> reviews = [];
        foreach (var space in spaces) {
            var match = space.Joining(destinations, joined);
            if (match is not null) joined.Add(match.Id);
            bool included = match is not null || created < room;
            if (included && match is null) created++;
            reviews.Add(ImportReviewSpace.Started(space, match, included,
                offers.GetValueOrDefault(space.Id) ?? []));
        }
        return new ImportReview(source, reviews, [], spaces.FirstOrDefault()?.Id, leftOut, room).Analyzed(session);
    }

    #endregion

    #region Actions - Editing

    /// `review` with `sourceId` joining the existing Space `destinationId` and
    /// taking its name and icon, or coming in new with its own name and icon when
    /// null. A destination the session does not hold changes nothing.
    internal ImportReview ChoosingDestination(Guid sourceId, Guid? destinationId, SessionState session) {
        ArgumentNullException.ThrowIfNull(session);
        var destination = destinationId is { } id ? session.ImportDestinations.FirstOrDefault(space => space.Id == id) : null;
        if (destinationId is not null && destination is null) return this;
        return Editing(sourceId, session, space => space with {
            DestinationId = destination?.Id,
            Customization = destination?.Customization ?? space.Source.Customization
        });
    }

    /// `review` bringing the tabs `tabIds` of `sourceId`, and with them the
    /// Space, or leaving them out.
    internal ImportReview IncludingTabs(Guid sourceId, IReadOnlyList<Guid> tabIds, bool included,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(tabIds);
        return Editing(sourceId, session, space => {
            var changed = space.Source.Tabs.Select(tab => tab.Id).Intersect(tabIds).ToHashSet();
            if (changed.Count == 0) return space;
            return included
                ? space with { Included = true, IncludedTabIds = space.Ordered(space.IncludedTabIds.Union(changed)) }
                : space with { IncludedTabIds = [.. space.IncludedTabIds.Where(tab => !changed.Contains(tab))] };
        });
    }

    /// `review` bringing the tab `tabId` of `sourceId` in `placement`, and
    /// with it the Space.
    internal ImportReview Placing(Guid sourceId, Guid tabId, TabPlacement placement,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(placement);
        return Editing(sourceId, session, space => space.Source.Tabs.All(tab => tab.Id != tabId) ? space : space with {
            Included = true,
            IncludedTabIds = space.Ordered(space.IncludedTabIds.Append(tabId)),
            Placements = [.. space.Placements.Where(choice => choice.TabId != tabId), new TabPlacementChoice(tabId, placement)]
        });
    }

    /// `review` bringing `sourceId` with every tab its destination does not
    /// already hold, or leaving it out with all of them.
    internal ImportReview IncludingSpace(Guid sourceId, bool included, SessionState session) =>
        Editing(sourceId, session, space => space with {
            Included = included,
            IncludedTabIds = included ? [.. space.Source.Tabs.Select(tab => tab.Id).Except(space.DuplicateTabIds)] : []
        });


    /// `review` installing the extension `extensionId` that `sourceId` offers,
    /// or leaving it out. An extension the Space does not offer changes nothing.
    internal ImportReview IncludingExtension(Guid sourceId, string extensionId, bool included,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(extensionId);
        return Editing(sourceId, session, space => {
            if (space.Extensions.All(extension => extension.ExtensionId != extensionId)) return space;
            var kept = space.IncludedExtensionIds.Where(id => id != extensionId);
            return space with { IncludedExtensionIds = [.. included ? kept.Append(extensionId) : kept] };
        });
    }

    /// `review` with `sourceId` taking the name and icon of `customization`,
    internal ImportReview Customizing(Guid sourceId, SpaceCustomization customization,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(customization);
        return Editing(sourceId, session, space => space with { Customization = customization });
    }

    /// `review` looking at `sourceId`, when it holds it.
    internal ImportReview Showing(Guid sourceId) =>
        Spaces.Any(space => space.Source.Id == sourceId) ? this with { ShownSpaceId = sourceId } : this;

    /// `review` with `edit` made to `sourceId`, unless it would bring the
    /// Space in new once the workspace is full, which changes nothing.
    private ImportReview Editing(Guid sourceId, SessionState session, Func<ImportReviewSpace, ImportReviewSpace> edit) {
        ArgumentNullException.ThrowIfNull(session);
        if (Spaces.FirstOrDefault(space => space.Source.Id == sourceId) is not { } current) return this;
        var edited = edit(current);
        if (edited.MakesNewSpace && !current.MakesNewSpace && Spaces.Count(space => space.MakesNewSpace) >= session.ImportRoom)
            return this;
        return (this with {
            Spaces = [.. Spaces.Select(space => space.Source.Id == sourceId ? edited : space)]
        }).Analyzed(session);
    }

    #endregion

    #region Actions - Analysis

    /// The review with what its choices mean against `session`: each Space's
    /// tabs its destination already holds and the destination's tabs it
    /// matches, the pinned tabs past each destination's limit, and the room
    /// the workspace has for new Spaces.
    internal ImportReview Analyzed(SessionState session) {
        ArgumentNullException.ThrowIfNull(session);
        var byId = session.ImportDestinations.ToDictionary(space => space.Id);
        var pinned = byId.ToDictionary(entry => entry.Key, entry => entry.Value.Tabs.Count(tab => tab.Placement == TabPlacement.Pinned));
        Dictionary<Guid, int> created = [];
        List<Guid> overflow = [];
        var spaces = Spaces.Select(space => {
            var analyzed = space.Analyzed(space.DestinationId is { } id ? byId.GetValueOrDefault(id) : null);
            if (!space.Included) return analyzed;
            var counts = space.DestinationId is null ? created : pinned;
            var key = space.DestinationId ?? space.Source.Id;
            var included = space.IncludedTabIds.ToHashSet();
            var placements = space.Placements.GroupBy(choice => choice.TabId).ToDictionary(group => group.Key, group => group.Last().Placement);
            foreach (var tab in space.Source.Tabs) {
                if (!included.Contains(tab.Id) || placements.GetValueOrDefault(tab.Id, tab.Placement) != TabPlacement.Pinned) continue;
                int count = counts.GetValueOrDefault(key);
                if (!TabPlacement.Pinned.Holds(count + 1)) overflow.Add(tab.Id);
                else counts[key] = count + 1;
            }
            return analyzed;
        }).ToArray();
        return this with { Spaces = spaces, OverflowTabIds = overflow, SpaceRoom = session.ImportRoom };
    }

    #endregion
}
