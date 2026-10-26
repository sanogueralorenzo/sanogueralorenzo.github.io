namespace CrestCore.Contracts;

#region Types

/// One extension a review installs: its `ExtensionId`, the `Name` it shows
/// and its `IconPath`, where the other browser keeps one, as the first Space
/// bringing it offers them, and the Spaces it installs in once imported, each
/// once.
public sealed record ImportExtensionInstall(string ExtensionId, string Name, string? IconPath, IReadOnlyList<Guid> SpaceIds);

#endregion

/// The review of what one browser brings, one Space at a time: each Space's
/// choices, the pinned tabs that move to a saved folder because their
/// destination holds no more, the Space the person is looking at, what the
/// read left out, and `SpaceRoom`, how many new Spaces the workspace has room
/// for before the review brings any. `BrowserTitle` names a browser setup
/// found by looking, which `Source` only stands for.
public sealed partial record SetupImportReview(ImportSource Source, IReadOnlyList<SetupReviewSpace> Spaces, IReadOnlyList<Guid> OverflowTabIds,
    Guid? ShownSpaceId, IReadOnlyList<ImportLeftOut> LeftOut, int SpaceRoom, string? BrowserTitle = null) {
    #region Variables

    /// The name of the browser the review brings from.
    [Resolved]
    public string Title => BrowserTitle ?? Source.Title;

    /// Whether the review brings any Space.
    [Resolved]
    public bool HasIncludedSpaces => Spaces.Any(space => space.Included);

    /// How many tabs the review brings.
    [Resolved]
    public int IncludedTabCount => Spaces.Where(space => space.Included).Sum(space => space.IncludedTabIds.Count);

    /// The Space after the one the person is looking at, which Next shows, or
    /// null on the last Space.
    [Resolved]
    public Guid? NextSpaceId {
        get {
            int shown = Spaces.Select(space => space.Source.Id).ToList().IndexOf(ShownSpaceId ?? Guid.Empty);
            if (shown < 0) return Spaces.FirstOrDefault()?.Source.Id;
            return shown + 1 < Spaces.Count ? Spaces[shown + 1].Source.Id : null;
        }
    }

    /// Whether the person is looking at the last Space, where Next imports.
    [Resolved]
    public bool ShowsLastSpace => Spaces.Count > 0 && ShownSpaceId == Spaces[^1].Source.Id;

    /// How many saved passwords the review brings.
    [Resolved]
    public int IncludedPasswordCount => Spaces.Where(space => space.Included && space.IncludesPasswords).Sum(space => space.PasswordCount);

    /// How many more of its Spaces the review can bring as new Spaces, beside
    /// those it brings: none once the workspace would be full.
    [Resolved]
    public int NewSpaceCapacity => Math.Max(0, SpaceRoom - Spaces.Count(space => space.MakesNewSpace));

    /// The extensions the review installs, each once, in the order the Spaces
    /// bringing them first offer it, with every Space it installs in: each
    /// bringing Space's destination, or the Space itself when it comes in new.
    [Resolved]
    public IReadOnlyList<ImportExtensionInstall> ExtensionInstalls => [.. Spaces
        .SelectMany(space => space.BroughtExtensions.Select(extension => (Extension: extension, Into: space.DestinationId ?? space.Source.Id)))
        .GroupBy(brought => brought.Extension.ExtensionId, StringComparer.Ordinal)
        .Select(group => new ImportExtensionInstall(group.Key, group.First().Extension.Name,
            group.Select(brought => brought.Extension.IconPath).FirstOrDefault(path => path is not null),
            [.. group.Select(brought => brought.Into).Distinct()]))];

    #endregion
}
