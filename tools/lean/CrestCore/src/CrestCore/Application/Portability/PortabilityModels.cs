using CrestCore.Contracts;

namespace CrestCore.Application;

/// A date in a property list: seconds since 2001.
internal readonly record struct PropertyListDate(double ReferenceSeconds);

/// A folder of another browser's session, with the identities that browser
/// spells for it and its parent: among the saved tabs, or among the open
/// tabs for a tab group, in the group's color.
internal sealed record SessionFolder(string SourceId, string Title, string? ParentSourceId, TabPlacement? Placement = null,
    TabGroupColor? Color = null);

/// A tab of another browser's session: the page it shows, where it sits, the
/// folder it sits in, when it was last active, where the browser knows, and
/// the split view it shows in, by the identity the browser spells for it.
internal sealed record SessionTab(string Title, ImportAddress Address, TabPlacement Placement, string? FolderSourceId,
    DateTimeOffset? LastActivatedAt, string? SplitSourceId = null);
