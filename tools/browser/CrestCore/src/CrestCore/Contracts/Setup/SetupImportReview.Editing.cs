using CrestCore.Application;

namespace CrestCore.Contracts;

/// Rules for reviewing an import before the workspace import applies it. An
/// imported Space joins the existing Space with the same name, tabs its
/// destination already holds are left out until the person asks for them,
/// pinned tabs past a destination's limit move to a saved folder, and no
/// choice brings more new Spaces than the workspace has room for. Each edit
/// answers the review as it leaves it, with what its choices mean against the
/// session worked out again.
public sealed partial record SetupImportReview {
    #region Actions - Starting

    /// The review a person starts from for the Spaces `source` brings, against
    /// `session`, looking at the first: each Space joins the existing Space of
    /// the same name, taking its name and look and leaving out the tabs it
    /// holds, or comes in as a new Space with its own. Each existing Space is
    /// joined by the first Space that matches it only, and a Space that would
    /// come in new once the workspace is full starts left out. A first
    /// launch's disposable Spaces are no destination, so everything comes in
    /// new in their place. `passwords` counts the saved passwords that belong
    /// with each Space, `extensions` lists the extensions each Space offers,
    /// all of them left on, and `leftOut` is what the read could not bring. A
    /// Space that comes in new wears `look`.
    internal static SetupImportReview Started(ImportSource source, IReadOnlyList<SpaceState> spaces,
        IReadOnlyDictionary<Guid, int> passwords, IReadOnlyList<ImportSpaceExtensions> extensions, IReadOnlyList<ImportLeftOut> leftOut,
        SessionState session, SetupLook look) {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(spaces);
        ArgumentNullException.ThrowIfNull(passwords);
        ArgumentNullException.ThrowIfNull(extensions);
        ArgumentNullException.ThrowIfNull(leftOut);
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(look);
        var destinations = session.ImportDestinations;
        var offers = extensions.GroupBy(entry => entry.SpaceId).ToDictionary(group => group.Key,
            group => (IReadOnlyList<ImportExtension>)[.. group.SelectMany(entry => entry.Extensions)
                .DistinctBy(extension => extension.ExtensionId, StringComparer.Ordinal)]);
        int room = session.ImportRoom, created = 0;
        HashSet<Guid> joined = [];
        List<SetupReviewSpace> reviews = [];
        foreach (var space in spaces) {
            var match = space.Joining(destinations, joined);
            if (match is not null) joined.Add(match.Id);
            bool included = match is not null || created < room;
            if (included && match is null) created++;
            reviews.Add(SetupReviewSpace.Started(space, match, included, passwords.GetValueOrDefault(space.Id),
                offers.GetValueOrDefault(space.Id) ?? [], look));
        }
        return new SetupImportReview(source, reviews, [], spaces.FirstOrDefault()?.Id, leftOut, room).Analyzed(session);
    }

    #endregion

    #region Actions - Editing

    /// `review` with `sourceId` joining the existing Space `destinationId` and
    /// taking its name and look, or coming in new with its own in `look` when
    /// null. A destination the session does not hold changes nothing.
    internal SetupImportReview ChoosingDestination(Guid sourceId, Guid? destinationId, SessionState session, SetupLook look) {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(look);
        var destination = destinationId is { } id ? session.ImportDestinations.FirstOrDefault(space => space.Id == id) : null;
        if (destinationId is not null && destination is null) return this;
        return Editing(sourceId, session, space => space with {
            DestinationId = destination?.Id,
            Customization = destination?.Customization ?? look.Applying(space.Source.Customization)
        });
    }

    /// `review` bringing the tabs `tabIds` of `sourceId`, and with them the
    /// Space, or leaving them out.
    internal SetupImportReview IncludingTabs(Guid sourceId, IReadOnlyList<Guid> tabIds, bool included,
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
    internal SetupImportReview Placing(Guid sourceId, Guid tabId, TabPlacement placement,
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
    internal SetupImportReview IncludingSpace(Guid sourceId, bool included, SessionState session) =>
        Editing(sourceId, session, space => space with {
            Included = included,
            IncludedTabIds = included ? [.. space.Source.Tabs.Select(tab => tab.Id).Except(space.DuplicateTabIds)] : []
        });

    /// `review` bringing the saved passwords of `sourceId`, or leaving them out.
    internal SetupImportReview IncludingPasswords(Guid sourceId, bool included, SessionState session) =>
        Editing(sourceId, session, space => space with { IncludesPasswords = included });

    /// `review` installing the extension `extensionId` that `sourceId` offers,
    /// or leaving it out. An extension the Space does not offer changes nothing.
    internal SetupImportReview IncludingExtension(Guid sourceId, string extensionId, bool included,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(extensionId);
        return Editing(sourceId, session, space => {
            if (space.Extensions.All(extension => extension.ExtensionId != extensionId)) return space;
            var kept = space.IncludedExtensionIds.Where(id => id != extensionId);
            return space with { IncludedExtensionIds = [.. included ? kept.Append(extensionId) : kept] };
        });
    }

    /// `review` with `sourceId` taking the name and look of `customization`,
    /// its look kept within the ranges every device draws.
    internal SetupImportReview Customizing(Guid sourceId, SpaceCustomization customization,
        SessionState session) {
        ArgumentNullException.ThrowIfNull(customization);
        var kept = customization with { Branding = SpaceBranding.Normalized(customization.Branding) };
        return Editing(sourceId, session, space => space with { Customization = kept });
    }

    /// `review` looking at `sourceId`, when it holds it.
    internal SetupImportReview Showing(Guid sourceId) =>
        Spaces.Any(space => space.Source.Id == sourceId) ? this with { ShownSpaceId = sourceId } : this;

    /// `review` with `edit` made to `sourceId`, unless it would bring the
    /// Space in new once the workspace is full, which changes nothing.
    private SetupImportReview Editing(Guid sourceId, SessionState session, Func<SetupReviewSpace, SetupReviewSpace> edit) {
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

    #region Actions - Passwords

    /// Where each of `passwords` goes once the review is imported into
    /// `session`: the destination of each reviewed Space the password belongs
    /// with that brings its passwords, leaving out a destination `session` no
    /// longer holds or `isLocked` holds shut. A password whose Space does not
    /// bring its passwords goes nowhere, never to another profile's Space.
    internal ImportPasswordRoutes PasswordRoutes(IReadOnlyList<ImportPasswordSource> passwords, SessionState session,
        Func<SpaceState, bool> isLocked) {
        ArgumentNullException.ThrowIfNull(passwords);
        ArgumentNullException.ThrowIfNull(session);
        ArgumentNullException.ThrowIfNull(isLocked);
        var reviewed = Spaces.Select(space => space.Source).ToArray();
        var destinations = Spaces.Where(space => space.BringsPasswords)
            .ToDictionary(space => space.Source.Id, space => space.DestinationId ?? space.Source.Id);
        var open = session.Spaces.Where(space => !isLocked(space)).Select(space => space.Id).ToHashSet();
        var sites = SpaceSites.Of(reviewed);
        return new([.. passwords.Select(password => new ImportPasswordRoute([.. Source.SpacesFor(password, reviewed, sites)
            .Where(destinations.ContainsKey).Select(spaceId => destinations[spaceId]).Distinct().Where(open.Contains)]))]);
    }

    #endregion

    #region Actions - Analysis

    /// The review with what its choices mean against `session`: each Space's
    /// tabs its destination already holds and the destination's tabs it
    /// matches, the pinned tabs past each destination's limit, and the room
    /// the workspace has for new Spaces.
    internal SetupImportReview Analyzed(SessionState session) {
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
