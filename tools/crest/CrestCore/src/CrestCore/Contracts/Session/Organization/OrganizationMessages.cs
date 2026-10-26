namespace CrestCore.Contracts;

#region Rejections - Folders

/// The Space already holds a folder with this identity.
public sealed record FolderAlreadyExists(Guid FolderId) : Rejection;

/// The folder would move into itself or into one of its own folders.
public sealed record FolderCycle(Guid FolderId) : Rejection;

/// The folder, or the deepest folder inside it, would sit `Limit` levels deep
/// or deeper.
public sealed record FolderDepthLimitReached(int Limit) : Rejection;

/// The Space already holds `Limit` folders.
public sealed record FolderLimitReached(int Limit) : Rejection;

/// The folder or tabs cannot go where the edit places them: the section holds
/// no folders, the folder named to hold them is in another section, or the
/// folder or tab named to go before is elsewhere or moves with them.
public sealed record InvalidFolderPlacement : Rejection;

/// A folder's symbol is an SF Symbol name or an emoji, never empty and never
/// longer than `MaximumBytes` in UTF-8.
public sealed record InvalidFolderSymbol(int MaximumBytes) : Rejection;

/// The Space holds no folder with this identity.
public sealed record UnknownFolder(Guid FolderId) : Rejection;

#endregion

#region Rejections - Splits

/// The tab is already a member of that split.
public sealed record AlreadyInSplit(Guid TabId) : Rejection;

/// The icon given for the split is no emoji: its first character does not
/// present as one.
public sealed record InvalidSplitIcon(Guid GroupId) : Rejection;

/// Stepping the tab `Offset` members along its split would move nothing.
public sealed record NoSplitStep(Guid TabId, int Offset) : Rejection;

/// The tabs would land between two members of a split they do not belong to.
public sealed record SplitBoundary : Rejection;

/// The split already holds `Limit` tabs.
public sealed record SplitLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Split View needs 2 to %lld tabs. Select fewer tabs or use a smaller split.";

    #endregion
}

/// No split in the Space has this identity, or it has fewer than two tabs.
public sealed record UnknownSplitGroup(Guid GroupId) : Rejection;

/// Only a page can join a split or keep its page loaded, and a Start Page or
/// a native view is not one.
public sealed record WebPagesOnly(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This action requires webpage tabs. Deselect built-in pages first.";

    #endregion
}

#endregion
