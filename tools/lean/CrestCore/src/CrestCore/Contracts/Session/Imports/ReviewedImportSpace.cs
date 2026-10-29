namespace CrestCore.Contracts;

/// Explicit native review choices for one atomic workspace import.
public sealed record ReviewedImportSpace(SpaceState Source, bool Included, Guid? DestinationId,
    SpaceCustomization Customization, IReadOnlyList<Guid> IncludedTabIds, IReadOnlyList<TabPlacementChoice> Placements);
